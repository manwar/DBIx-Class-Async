
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

# 1. Setup real temporary SQLite database
my ($fh, $filename) = tempfile(SUFFIX => '.db', UNLINK => 1);
my $dsn = "dbi:SQLite:dbname=$filename";

# Initialize and seed the DB so all_future has something to find
my $base_schema = TestSchema->connect($dsn);
$base_schema->deploy();
$base_schema->resultset('User')->create({
    id    => 1,
    name  => 'BottomUp User',
    email => 'bu@test.com'
});

# 2. Initialize the Async Engine
my $loop = IO::Async::Loop->new;
my $async_schema = DBIx::Class::Async::Schema->connect($dsn, {
    schema_class => 'TestSchema',
    async_loop   => $loop,
    workers      => 2,
});


subtest 'ResultSet Delete - Path A (Direct)' => sub {
    # 1. Setup: Create a specific user to kill
    my $name = "Delete Me Direct";
    $async_schema->resultset('User')->create({ name => $name, email => 'direct@test.com' })->get;

    # 2. Path A: Simple hash condition, no complex attributes
    my $rs = $async_schema->resultset('User')->search({ name => $name });

    my $future = $rs->delete();
    my $count = $future->get;

    is($count, 1, 'Path A: Deleted exactly 1 row');

    # 3. Verify
    my $exists = $async_schema->resultset('User')->search({ name => $name })->count_future->get;
    is($exists, 0, 'User no longer exists in DB');
};

subtest 'ResultSet Delete - Path B (Safe Path via all)' => sub {
    # 1. Setup: Create multiple rows
    $async_schema->resultset('User')->create({ name => "Batch 1", email => 'b1@test.com' })->get;
    $async_schema->resultset('User')->create({ name => "Batch 2", email => 'b2@test.com' })->get;
    $async_schema->resultset('User')->create({ name => "Batch 3", email => 'b3@test.com' })->get;

    # 2. Path B: Adding 'rows' or 'offset' forces the safe ID-mapping path
    # We target 2 rows specifically using LIMIT
    my $rs = $async_schema->resultset('User')->search(
        { name => { -like => 'Batch %' } },
        { rows => 2, order_by => 'id' }
    );

    # This should trigger delete_all() internally
    my $future = $rs->delete();
    my $count = $future->get;

    is($count, 2, 'Path B: Correctly identified and deleted 2 rows via mapping');

    # 3. Verify: Only 1 batch user should remain
    my $remaining = $async_schema->resultset('User')->search({
        name => { -like => 'Batch %' }
    })->count_future->get;

    is($remaining, 1, 'Exactly one batch user remains');
};

subtest 'ResultSet Delete - Empty Resultset' => sub {
    my $rs = $async_schema->resultset('User')->search({ id => 999999 });

    my $count = $rs->delete->get;
    is($count, 0, 'Deleting an empty resultset returns 0 and does not crash');
};

done_testing();
