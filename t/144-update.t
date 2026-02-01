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

$schema->resultset('User')->create({
    id    => 1,
    name  => 'BottomUp User',
    email => 'bu@test.com'
})->get;

subtest 'ResultSet Update - Path A (Fast Path)' => sub {
    my $rs = $schema->resultset('User')->search({ id => 1 });

    # 1. Dispatch the update
    # This should trigger Path A because there are no attrs
    my $future = $rs->update({ name => 'Updated Name' });

    isa_ok($future, 'Future', 'update() returns a Future');
    my $rows_affected = $future->get;

    is($rows_affected, 1, 'Successfully updated 1 row');

    # 2. Verify the update by fetching a fresh ResultSet
    # (Don't use the old $rs because it might have the old name cached in _rows!)
    my $fresh_rs = $schema->resultset('User')->search({ id => 1 });
    my $user = $fresh_rs->next->get;

    is($user->name, 'Updated Name', 'Database reflects the update');
};

subtest 'ResultSet Update - Path B (Safe Path)' => sub {
    # Adding 'rows => 1' forces Path B
    my $rs = $schema->resultset('User')->search(
        { id => 1 },
        { rows => 1 }
    );

    my $future = $rs->update({ name => 'Path B Winner' });

    # Check logs for "Taking Path B" and "update_all"
    my $rows_affected = $future->get;
    is($rows_affected, 1, 'Safe Path updated correct number of rows');

    # Verify
    my $user = $schema->resultset('User')->find(1)->get;
    is($user->name, 'Path B Winner', 'Data updated via Safe Path');
};

done_testing;
