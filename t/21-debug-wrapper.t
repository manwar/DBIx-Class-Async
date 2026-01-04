#!/usr/bin/env perl
# t/debug-wrapper.t - Debug schema wrapper
use strict;
use warnings;

use FindBin qw($Bin);
use lib "$Bin/../lib";
use lib "$Bin/lib";

print "1..10\n";

# Test 1: Load modules
eval {
    require DBIx::Class::Async;
    require DBIx::Class::Async::Schema;
    require DBIx::Class::Async::ResultSet;
    require DBIx::Class::Async::Row;
    require TestSchema;
    print "ok 1 - Modules loaded\n";
    1;
} or do {
    print "not ok 1 - $@\n";
    exit 1;
};

# Setup database
use DBI;
my $dbh = DBI->connect("dbi:SQLite:dbname=debug.db", "", "", {
    RaiseError => 1,
    PrintError => 0,
});

$dbh->do("DROP TABLE IF EXISTS users");
$dbh->do("DROP TABLE IF EXISTS orders");

$dbh->do("CREATE TABLE users (id INTEGER PRIMARY KEY AUTOINCREMENT, name VARCHAR(50), email VARCHAR(100), active INTEGER DEFAULT 1)");
$dbh->do("CREATE TABLE orders (id INTEGER PRIMARY KEY AUTOINCREMENT, user_id INTEGER, amount DECIMAL(10,2), status VARCHAR(20) DEFAULT 'pending')");
$dbh->disconnect;

print "ok 2 - Database created\n";

# Test 3: Create async instance directly
use IO::Async::Loop;
my $loop = IO::Async::Loop->new;

my $async = DBIx::Class::Async->new(
    schema_class => 'TestSchema',
    connect_info => ['dbi:SQLite:dbname=debug.db'],
    workers => 1,
    loop => $loop,
);

print "ok 3 - Async instance created\n";

# Test 4: Create user directly (this works)
my $user_hash = $async->create('User', {
    name => 'Debug User',
    email => 'debug@example.com',
})->get;

print "ok 4 - Direct create worked, got hashref with keys: " . join(', ', keys %$user_hash) . "\n";

# Test 5: Now test Schema wrapper
my $schema = DBIx::Class::Async::Schema->connect(
    "dbi:SQLite:dbname=debug.db",
    undef,
    undef,
    {},
    {
        workers => 1,
        schema_class => 'TestSchema',
        loop => $loop
    }
);

print "ok 5 - Schema wrapper connected\n";

# Test 6: Get resultset
my $rs = $schema->resultset('User');
print "ok 6 - Got resultset: " . ref($rs) . "\n";

# Test 7: Check resultset type
if ($rs->isa('DBIx::Class::Async::ResultSet')) {
    print "ok 7 - ResultSet is correct type\n";
} else {
    print "not ok 7 - ResultSet is wrong type: " . ref($rs) . "\n";
}

# Test 8: Try create through wrapper
my $create_future = $rs->create({
    name => 'Wrapper User',
    email => 'wrapper@example.com',
});

print "ok 8 - Create future created\n";

# Test 9: Get result
eval {
    my $user_obj = $create_future->get;
    print "ok 9 - Got user object: " . ref($user_obj) . "\n";

    # Test 10: Try to access properties
    if ($user_obj->isa('DBIx::Class::Async::Row')) {
        print "ok 10 - User is Row object\n";

        # Try to access name
        eval {
            my $name = $user_obj->name;
            print "# Got name: $name\n";
        } or do {
            print "# Failed to get name: $@\n";
        };

        # Try get_column
        eval {
            my $name = $user_obj->get_column('name');
            print "# get_column('name'): $name\n";
        } or do {
            print "# get_column failed: $@\n";
        };

        # Dump the object
        print "# Object dump:\n";
        foreach my $key (keys %$user_obj) {
            print "#   $key: " . (ref $user_obj->{$key} ? ref $user_obj->{$key} : $user_obj->{$key}) . "\n";
        }
    } else {
        print "not ok 10 - User is not Row object: " . ref($user_obj) . "\n";
    }

    1;
} or do {
    my $error = $@;
    print "not ok 9 - Failed to get user: $error\n";
    print "not ok 10 - Skipped\n";
};

# Cleanup
$async->disconnect;
unlink 'debug.db';
