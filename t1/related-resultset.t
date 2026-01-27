
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

# 1. Setup Database
my ($fh, $filename) = tempfile(SUFFIX => '.db', UNLINK => 1);
my $dsn = "dbi:SQLite:dbname=$filename";
TestSchema->connect($dsn)->deploy();

# 2. Setup Async
my $loop = IO::Async::Loop->new;
my $async_schema = DBIx::Class::Async::Schema->connect($dsn, {
    schema_class => 'TestSchema',
    async_loop   => $loop,
});

sub wait_for {
    my $f = shift;
    my $res;
    return $f->result if $f->is_ready;
    $f->on_ready(sub {
        my $f = shift;
        $res = eval { $f->result };
        warn "Error: $@" if $@;
        $loop->stop;
    });
    $loop->run;
    return $res;
}

# 3. Seed Data
my $schema = TestSchema->connect($dsn);
# User 1: 40 years old, 1 order
my $u1 = $schema->resultset('User')->create({ name => 'Bob', age => 40 });
$u1->create_related('orders', { amount => 99.99, status => 'shipped' });

# User 2: 30 years old, 2 orders
my $u2 = $schema->resultset('User')->create({ name => 'Alice', age => 30 });
$u2->create_related('orders', { amount => 10.00, status => 'pending' });
$u2->create_related('orders', { amount => 20.00, status => 'pending' });

# --- TESTS ---

subtest 'related_resultset() filtering child by parent attribute' => sub {
    # 1. Filter Users by age (matching only Alice)
    my $users_rs = $async_schema->resultset('User')->search({ age => 30 });

    # 2. Pivot to Orders. This should result in:
    # SELECT me.* FROM orders me JOIN users user ON ... WHERE user.age = 30
    my $orders_rs = $users_rs->related_resultset('orders');

    # Verify the internal state before executing
    is($orders_rs->{_attrs}{join}, 'user', "Detected and applied reverse relationship 'user'");
    ok(exists $orders_rs->{_cond}{'user.age'}, "Condition was prefixed with reverse rel name");

    # 3. Execute
    my $orders = wait_for($orders_rs->all);
    is(scalar @$orders, 2, "Found both of Alice's orders via the parent age filter");
};

subtest 'related_resultset() with additional child filters' => sub {
    my $users_rs = $async_schema->resultset('User')->search({ age => 30 });

    # Pivot to orders, but add an additional filter on the orders themselves
    my $orders_rs = $users_rs->related_resultset('orders')
                             ->search({ amount => { '>', 15 } });

    my $orders = wait_for($orders_rs->all);
    is(scalar @$orders, 1, "Filtered down to 1 order matching both parent and child criteria");
    is($orders->[0]->amount, 20.00, "Retrieved correct high-value order for Alice");
};

done_testing();
