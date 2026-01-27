

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
my (undef, $db_file) = tempfile(SUFFIX => '.db', UNLINK => 1);
my $async_schema = DBIx::Class::Async::Schema->connect("dbi:SQLite:dbname=$db_file", {
    schema_class => 'TestSchema',
    async_loop   => $loop,
});

$loop->await($async_schema->deploy);

subtest 'Dependent Cross-Table Transaction' => sub {
    # We want to create a User, and then an Order for that User ID
    my $txn_f = $async_schema->txn_do([
        {
            name      => 'new_user',
            action    => 'create',
            resultset => 'User',
            data      => { name => 'Alice', email => 'alice@example.com' }
        },
        {
            action    => 'create',
            resultset => 'Order',
            data      => {
                user_id => '$new_user.id', # Worker will resolve this!
                amount  => 150.00
            }
        }
    ]);

    my $inner_f = $loop->await($txn_f);
    my $res = $inner_f->get;

    ok($res->{success}, "Transaction completed");

    # Final Verification: Does the order actually point to the user?
    my $search_f = $async_schema->resultset('Order')->search_future({});
    my $orders = ($loop->await($search_f))->get;

    my $user_search_f = $async_schema->resultset('User')->search_future({ name => 'Alice' });
    my $users = ($loop->await($user_search_f))->get;

    is($orders->[0]{user_id}, $users->[0]{id}, "Order linked to correct User ID via register");
};

subtest 'Raw SQL String Interpolation' => sub {
    # 1. Create a user to get an ID
    # 2. Use that ID inside a raw SQL update string
    my $txn_f = $async_schema->txn_do([
        {
            name      => 'target_user',
            action    => 'create',
            resultset => 'User',
            data      => { name => 'Original Name', email => 'raw@test.com' }
        },
        {
            action    => 'raw',
            # We are testing if '$target_user.id' is swapped inside the SQL string
            sql       => "UPDATE users SET name = 'Modified for ID \$target_user.id' WHERE id = \$target_user.id",
        }
    ]);

    my $res = ($loop->await($txn_f))->get;
    ok($res->{success}, "Transaction with Raw SQL interpolation succeeded");

    # Verify the update actually worked
    my $search_f = $async_schema->resultset('User')->search_future({ email => 'raw@test.com' });
    my $users = ($loop->await($search_f))->get;

    my $user_id = $users->[0]{id};
    my $expected_name = "Modified for ID $user_id";

    is($users->[0]{name}, $expected_name, "Raw SQL string was interpolated correctly with the real ID");

    done_testing();
};

done_testing();
