#!/usr/bin/env perl

use strict;
use warnings;

use Test::More;
use Test::Deep;
use File::Temp;
use Test::Exception;
use IO::Async::Loop;
use DBIx::Class::Async::Schema;

use lib 't/lib';

my $loop           = IO::Async::Loop->new;
my ($fh, $db_file) = File::Temp::tempfile(SUFFIX => '.db', UNLINK => 1);
my $schema         = DBIx::Class::Async::Schema->connect(
    "dbi:SQLite:dbname=$db_file", undef, undef, {},
    { workers      => 2,
      schema_class => 'TestSchema',
      async_loop   => $loop,
      cache_ttl    => 60,
    },
);

$schema->await($schema->deploy({ add_drop_table => 1 }));

subtest 'Standard Populate (Array of Arrays)' => sub {
    my $rs = $schema->resultset('User');
    my $f = $rs->populate([
        [qw/ name age /],
        [ 'Dave',    50 ],
        [ 'Eve',     25 ],
    ]);

    my $res = $schema->await($f);
    is(ref $res, 'ARRAY', "Returns an arrayref");
    is(scalar @$res, 2, "Created 2 rows");
    is($res->[0]{name}, 'Dave', "First record is Dave");
};

subtest 'Bulk Populate (HashRefs)' => sub {
    my $rs = $schema->resultset('User');
    my $f = $rs->populate_bulk([
        { name => 'Frank', age => 30 },
        { name => 'Grace', age => 22 },
    ]);

    my $res = $schema->await($f);
    ok($res, "populate_bulk returns truthy success (1)");

    # Verify count
    my $count_f = $rs->count;
    is($schema->await($count_f), 4, "Total count is now 4");
};

subtest 'Prefetch Proxy Logic' => sub {
    # Testing the proxy construction (non-blocking)
    my $rs = $schema->resultset('User');
    my $prefetched_rs = $rs->prefetch('posts');

    isa_ok($prefetched_rs, 'DBIx::Class::Async::ResultSet', "prefetch() returns a new RS proxy");
    is($prefetched_rs->{_attrs}->{prefetch}, 'posts', "Prefetch attribute correctly stored in proxy");

    # Ensure the original RS was not modified (immutability)
    ok(!exists $rs->{_attrs}->{prefetch}, "Original ResultSet remains clean");
};

subtest 'Execution with Prefetch' => sub {
    # 1. Setup Data using a standard connection
    my $dsn = "dbi:SQLite:dbname=$db_file";
    my $native_schema = TestSchema->connect($dsn);
    my $dave = $native_schema->resultset('User')->find({ name => 'Dave' });

    $dave->create_related('orders', {
        amount => 42.00,
        status => 'shipped'
    });

    # 2. Test the Async prefetch
    my $f = $schema->resultset('User')
                   ->search({ 'me.name' => 'Dave' })
                   ->prefetch('orders')
                   ->next;

    my $user = $schema->await($f);

    # 3. Assertions
    is($user->name, 'Dave', "Found Dave object");

    # Access prefetched data (now using 'status' instead of 'order_number')
    my $orders = $user->{_relationship_data}{orders};
    is(ref $orders, 'ARRAY', "Orders were prefetched");
    is($orders->[0]{status}, 'shipped', "Order status is correct");
};

done_testing;
