#!/usr/bin/env perl

use strict;
use warnings;

use Test::More;
use Test::Deep;
use File::Temp;
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

# User 1: 40 years old, 1 order
my $u1 = $schema->resultset('User')->create({ name => 'Bob', age => 40 })->get;
$u1->create_related('orders', { amount => 99.99, status => 'shipped' })->get;

# User 2: 30 years old, 2 orders
my $u2 = $schema->resultset('User')->create({ name => 'Alice', age => 30 })->get;
$u2->create_related('orders', { amount => 10.00, status => 'pending' })->get;
$u2->create_related('orders', { amount => 20.00, status => 'pending' })->get;

subtest 'related_resultset() filtering child by parent attribute' => sub {
    # 1. Filter Users by age
    my $users_rs = $schema->resultset('User')->search({ age => 30 });

    # 2. Pivot to Orders.
    my $orders_rs = $users_rs->related_resultset('orders');

    # Verify internal state
    is($orders_rs->{_attrs}{join}, 'user', "Detected and applied reverse relationship 'user'");
    ok(exists $orders_rs->{_cond}{'user.age'}, "Condition was prefixed with reverse rel name");

    # 3. Execute and await
    my $orders = $schema->await($orders_rs->all);
    is(scalar @$orders, 2, "Found both of Alice's orders via the parent age filter");
};

subtest 'related_resultset() with additional child filters' => sub {
    my $users_rs = $schema->resultset('User')->search({ age => 30 });

    my $orders_rs = $users_rs->related_resultset('orders')
                             ->search({ amount => { '>', 15 } });

    my $orders = $schema->await($orders_rs->all);
    is(scalar @$orders, 1, "Filtered down to 1 order matching both parent and child criteria");
    is($orders->[0]->amount, 20.00, "Retrieved correct high-value order for Alice");
};

$schema->disconnect;

done_testing;
