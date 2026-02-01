#!/usr/bin/env perl

use strict;
use warnings;

use Test::More;
use File::Temp;
use IO::Async::Loop;
use DBIx::Class::Async::Schema;

use lib 't/lib';

my $loop           = IO::Async::Loop->new;
my ($fh, $db_file) = File::Temp::tempfile(SUFFIX => '.db', UNLINK => 1);

# FIX: For manual transaction testing, we use 1 worker to ensure
# the same DB handle is used for BEGIN and COMMIT/ROLLBACK.
my $schema = DBIx::Class::Async::Schema->connect(
    "dbi:SQLite:dbname=$db_file", undef, undef, {},
    { workers      => 1,
      schema_class => 'TestSchema',
      async_loop   => $loop,
    },
);

$schema->await($schema->deploy({ add_drop_table => 1 }));

subtest "Manual Transaction: Rollback" => sub {
    # 1. Start Transaction
    $schema->txn_begin->get;

    # 2. Create a user
    $schema->resultset('User')->create({
        name => 'Ghost',
        email => 'ghost@test.com'
    })->get;

    # 3. Roll it back
    $schema->txn_rollback->get;

    # 4. Verify the database is empty
    my $count = $schema->resultset('User')->count->get;
    is($count, 0, "Rollback successful: User was not saved");

    done_testing;
};

subtest "Manual Transaction: Commit" => sub {
    # Clear any leftover state if needed (though rollback should have handled it)
    $schema->resultset('User')->delete_all->get;

    $schema->txn_begin->get;

    $schema->resultset('User')->create({
        name => 'Permanent',
        email => 'perm@test.com'
    })->get;

    $schema->txn_commit->get;

    my $count = $schema->resultset('User')->count->get;
    is($count, 1, "Commit successful: User was saved");

    done_testing;
};

$schema->disconnect;
done_testing;
