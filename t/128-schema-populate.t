#!/usr/bin/env perl

use strict;
use warnings;
use Test::More;
use IO::Async::Loop;
use File::Temp qw(tempfile);
use DBIx::Class::Async::Schema;

use lib 't/lib';
use TestSchema;

BEGIN {
    $SIG{__WARN__} = sub {};
}

my $loop = IO::Async::Loop->new;
my (undef, $db_file) = tempfile(SUFFIX => '.db', UNLINK => 1);

my $async_schema = DBIx::Class::Async::Schema->connect(
    "dbi:SQLite:dbname=$db_file",
    undef, undef,
    { workers => 1, schema_class => 'TestSchema', async_loop => $loop }
);

# CRITICAL: Deploy the tables so the Worker can see them!
# We use a synchronous deploy here because it's setup code.
$async_schema->deploy->get;

subtest "Bulk Populate" => sub {
    my $data = [
        { name => 'User A', email => 'a@test.com', age => 25 },
        { name => 'User B', email => 'b@test.com', age => 30 },
        { name => 'User C', email => 'c@test.com', age => 35 },
    ];

    # Test the Schema-level port
    my $future = eval { $async_schema->populate('User', $data) };
    ok($future, "populate() returned a future") or diag $@;

    my $res = $future->get;
    ok($res, "Bulk populate completed successfully");

    # Verify the data actually made it to the DB
    my $count_future = $async_schema->resultset('User')->count_future;
    is($count_future->get, 3, "All 3 rows were inserted via populate");
};

done_testing;
