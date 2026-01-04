#!/usr/bin/env perl
# t/debug-schema.t - Debug schema wrapper
use strict;
use warnings;

use FindBin qw($Bin);
use lib "$Bin/../lib";
use lib "$Bin/lib";

# MUST use IO::Async::Loop
use IO::Async::Loop;

print "1..10\n";

# Test 1-3: Load modules
eval {
    require DBIx::Class::Async;
    print "ok 1 - DBIx::Class::Async loaded\n";
    1;
} or do {
    print "not ok 1 - $@\n";
    exit 1;
};

eval {
    require DBIx::Class::Async::Schema;
    print "ok 2 - DBIx::Class::Async::Schema loaded\n";
    1;
} or do {
    print "not ok 2 - $@\n";
    exit 1;
};

eval {
    require TestSchema;
    print "ok 3 - TestSchema loaded\n";
    1;
} or do {
    print "not ok 3 - $@\n";
    exit 1;
};

# Test 4: Create database
use DBI;
my $dbh = DBI->connect("dbi:SQLite:dbname=:memory:", "", "", {
    RaiseError => 1,
    PrintError => 0,
});

$dbh->do("CREATE TABLE users (id INTEGER PRIMARY KEY AUTOINCREMENT, name VARCHAR(50), email VARCHAR(100), active INTEGER DEFAULT 1)");
$dbh->do("CREATE TABLE orders (id INTEGER PRIMARY KEY AUTOINCREMENT, user_id INTEGER, amount DECIMAL(10,2), status VARCHAR(20) DEFAULT 'pending')");
$dbh->disconnect;

print "ok 4 - Database created\n";

# Test 5: Create loop
my $loop = IO::Async::Loop->new;
print "ok 5 - Loop created\n";

# Test 6: Connect with Schema wrapper
my $schema;
eval {
    $schema = DBIx::Class::Async::Schema->connect(
        "dbi:SQLite:dbname=:memory:",
        undef,
        undef,
        {},
        {
            workers => 1,
            schema_class => 'TestSchema',
            loop => $loop
        }
    );
    print "ok 6 - Schema connected\n";
    1;
} or do {
    print "not ok 6 - $@\n";
    exit 1;
};

# Test 7: Get resultset
my $rs;
eval {
    $rs = $schema->resultset('User');
    print "ok 7 - Got resultset\n";
    1;
} or do {
    print "not ok 7 - $@\n";
    exit 1;
};

# Test 8: Try to create (this is where it fails)
eval {
    my $future = $rs->create({
        name => 'Debug Test',
        email => 'debug@example.com',
    });

    print "ok 8 - Future created\n";

    # Try to get the result
    my $result = $future->get;

    if ($result) {
        print "ok 9 - Got result: " . ref($result) . "\n";
        print "ok 10 - Test passed\n";
    } else {
        print "not ok 9 - No result\n";
        print "not ok 10 - Test failed\n";
    }

    1;
} or do {
    my $error = $@;
    print "not ok 8 - Future failed: $error\n";
    print "not ok 9 - Skipped\n";
    print "not ok 10 - Skipped\n";
};
