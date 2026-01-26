
use strict;
use warnings;
use Test::More;
use File::Temp qw(tempfile);
use IO::Async::Loop;
use lib 'lib';
use TestSchema;
use DBIx::Class::Async::Schema;

BEGIN {
    $SIG{__WARN__} = sub {};
}

# 1. Database Setup (File-based for multi-process access)
my ($fh, $filename) = tempfile(SUFFIX => '.db', UNLINK => 1);
my $dsn = "dbi:SQLite:dbname=$filename";

# Deploy the schema so tables exist for the workers
TestSchema->connect($dsn)->deploy();

# 2. Async Setup
my $loop = IO::Async::Loop->new;
my $async_schema = DBIx::Class::Async::Schema->connect($dsn, {
    schema_class => 'TestSchema',
    async_loop   => $loop,
    workers      => 2,
});

# Helper to block until a Future is ready
sub wait_for {
    my $f = shift;
    my $result;
    $f->on_ready(sub {
        my $f = shift;
        if ($f->is_done) {
            $result = $f->result;
        } else {
            diag "Future failed: " . ($f->failure // 'unknown error');
            $result = undef;
        }
        $loop->stop;
    });
    $loop->run;
    return $result;
}

# --- TESTS ---

subtest 'Standard Populate (Array of Arrays)' => sub {
    my $rs = $async_schema->resultset('User');
    my $f = $rs->populate([
        [qw/ name age /],
        [ 'Dave',    50 ],
        [ 'Eve',     25 ],
    ]);

    my $res = wait_for($f);
    is(ref $res, 'ARRAY', "Returns an arrayref");
    is(scalar @$res, 2, "Created 2 rows");
    is($res->[0]{name}, 'Dave', "First record is Dave");
};

subtest 'Bulk Populate (HashRefs)' => sub {
    my $rs = $async_schema->resultset('User');
    my $f = $rs->populate_bulk([
        { name => 'Frank', age => 30 },
        { name => 'Grace', age => 22 },
    ]);

    my $res = wait_for($f);
    ok($res, "populate_bulk returns truthy success (1)");

    # Verify count
    my $count_f = $rs->count;
    is(wait_for($count_f), 4, "Total count is now 4");
};

subtest 'Prefetch Proxy Logic' => sub {
    # Testing the proxy construction (non-blocking)
    my $rs = $async_schema->resultset('User');
    my $prefetched_rs = $rs->prefetch('posts');

    isa_ok($prefetched_rs, 'DBIx::Class::Async::ResultSet', "prefetch() returns a new RS proxy");
    is($prefetched_rs->{_attrs}->{prefetch}, 'posts', "Prefetch attribute correctly stored in proxy");

    # Ensure the original RS was not modified (immutability)
    ok(!exists $rs->{_attrs}->{prefetch}, "Original ResultSet remains clean");
};

subtest 'Execution with Prefetch' => sub {
    # 1. Setup Data using a standard connection
    my $schema = TestSchema->connect($dsn);
    my $dave = $schema->resultset('User')->find({ name => 'Dave' });

    $dave->create_related('orders', {
        amount => 42.00,
        status => 'shipped'
    });

    # 2. Test the Async prefetch
    my $f = $async_schema->resultset('User')
                         ->search({ 'me.name' => 'Dave' })
                         ->prefetch('orders')
                         ->next;

    my $user = wait_for($f);

    # 3. Assertions
    is($user->name, 'Dave', "Found Dave object");

    # Access prefetched data (now using 'status' instead of 'order_number')
    my $orders = $user->{_relationship_data}{orders};
    is(ref $orders, 'ARRAY', "Orders were prefetched");
    is($orders->[0]{status}, 'shipped', "Order status is correct");

    done_testing();
};
done_testing();
