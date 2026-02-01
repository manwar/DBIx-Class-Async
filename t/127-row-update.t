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

subtest 'Row Object update() - Existing Record' => sub {
    my $rs = $schema->resultset('User');

    # 1. Setup: Create initial record
    my $user = $rs->create({ name => 'Original Name', email => 'orig@test.com' })->get;
    my $id = $user->id;

    # 2. Modify and Update
    $user->name('Updated Name');

    # Check dirty state before update (if your Row class implements it)
    if ($user->can('get_dirty_columns')) {
        my %dirty = $user->get_dirty_columns;
        ok(exists $dirty{name}, 'Column "name" marked as dirty before update');
    }

    # 3. Commit
    my $returned_user = $user->update->get;

    # 4. Verifications
    is($returned_user->name, 'Updated Name', 'Returned object has new name');
    is($user->name, 'Updated Name', 'Original object updated in-place');

    if ($user->can('get_dirty_columns')) {
        my %dirty = $user->get_dirty_columns;
        is(keys %dirty, 0, 'Dirty flags cleared after success');
    }

    # 5. Database Verification
    my $db_check = $rs->find($id)->get;
    is($db_check->name, 'Updated Name', 'Database reflects change');
};

subtest 'Row Object update_or_insert() - New Record' => sub {
    my $rs = $schema->resultset('User');

    # 1. Create a new object (not in storage)
    my $new_user = $rs->new_result({ name => 'New User', email => 'new@test.com' });
    is($new_user->in_storage, 0, 'New object starts with in_storage = 0');

    # 2. Call update_or_insert (should trigger the create branch)
    $new_user->update_or_insert->get;

    # 3. Verifications
    ok($new_user->id, 'Object now has an auto-incremented ID: ' . $new_user->id);
    is($new_user->in_storage, 1, 'Object now marked as in_storage');

    # 4. Database Verification
    my $db_check = $rs->find($new_user->id)->get;
    ok($db_check, 'Found the newly inserted record in DB');
};

subtest 'Row Object update() - No Changes' => sub {
    my $user = $schema->resultset('User')->search({}, {rows => 1})->single->get;

    # Calling update with no dirty columns
    my $f = $user->update;

    # This should return immediately with Future->done($self)
    # as per your logic: return Future->done($self) unless keys %to_save;
    isa_ok($f, 'Future');
    my $res = $f->get;
    is($res, $user, 'Update with no changes returns the object immediately');
};

done_testing;
