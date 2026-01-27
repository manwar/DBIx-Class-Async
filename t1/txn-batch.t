
use strict;
use warnings;
use Test::More;
use IO::Async::Loop;
use DBIx::Class::Async::Schema;
use File::Temp qw(tempfile);
use lib 't/lib';
use TestSchema;

BEGIN {
    $SIG{__WARN__} = sub {};
}

my $loop = IO::Async::Loop->new;
my ($fh, $db_filename) = tempfile(SUFFIX => '.db', UNLINK => 1);
close($fh);

my $dsn = "dbi:SQLite:dbname=$db_filename";
my $async_schema = DBIx::Class::Async::Schema->connect($dsn, {
    schema_class => 'TestSchema',
    async_loop   => $loop,
    workers      => 1,
});

# Setup: Deploy
$loop->await($async_schema->deploy);

subtest 'Successful Batch' => sub {
    my $batch_f = $async_schema->txn_batch([
        {
            type      => 'create',
            resultset => 'User',
            data      => { name => 'Alice', email => 'alice@example.com' }
        },
        {
            type      => 'create',
            resultset => 'User',
            data      => { name => 'Bob', email => 'bob@example.com' }
        },
    ]);

    # Peel layers and extract hash
    my $inner_batch_f = $loop->await($batch_f);
    my $res = $inner_batch_f->get;

    is($res->{count}, 2, "Batch reports 2 successful operations");

    # Verify search
    my $search_f = $async_schema->resultset('User')->search_future({});
    my $inner_search_f = $loop->await($search_f);
    my $users = $inner_search_f->get;

    is(ref $users, 'ARRAY', "Search results is an ARRAY reference");
    is(scalar @$users, 2, "Both users exist in DB");

    done_testing();
};

subtest 'Atomic Rollback on Failure' => sub {
    my $batch_f = $async_schema->txn_batch([
        {
            type      => 'create',
            resultset => 'User',
            data      => { name => 'Charlie', email => 'charlie@example.com' }
        },
        {
            type      => 'update',
            resultset => 'User',
            id        => 999,
            data      => { name => 'NonExistent' }
        },
    ]);

    # Handle the expected failure
    my $inner_batch_f = $loop->await($batch_f);

    # In DBIx::Class::Async, failures come back as a failed Future
    ok($inner_batch_f->failure, "Batch failed as expected");
    like($inner_batch_f->failure, qr/Record not found/, "Error caught correctly");

    # Verify Rollback: Charlie should not exist
    my $search_f = $async_schema->resultset('User')->search_future({ name => 'Charlie' });
    my $inner_search_f = $loop->await($search_f);
    my $users = $inner_search_f->get;

    is(scalar @$users, 0, "Charlie was rolled back and does not exist");

    done_testing();
};

done_testing();
