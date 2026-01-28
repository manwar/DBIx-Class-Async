#!/usr/bin/env perl

use strict;
use warnings;
use Test::More;
use IO::Async::Loop;
use DBIx::Class::Async::Schema;

use lib 't/lib';
# Ensure TestSchema has a version for this test
{
    package TestSchema;
    use base 'DBIx::Class::Schema';
    our $VERSION = '1.2.3';
}

my $loop = IO::Async::Loop->new;
my $async_schema = DBIx::Class::Async::Schema->connect(
    "dbi:SQLite::memory:", undef, undef,
    { schema_class => 'TestSchema', async_loop => $loop }
);

subtest "Schema Version Introspection" => sub {
    # 1. Test the ported method
    my $version = eval { $async_schema->schema_version };
    ok(!$@, "schema_version() executed without error") or diag $@;

    # 2. Verify the value
    is($version, '1.2.3', "Correctly retrieved version from TestSchema");
};

subtest "Error Handling" => sub {
    # Delete the key from the nested hashref where the code actually looks
    local $async_schema->{_async_db}->{_schema_class} = undef;

    eval { $async_schema->schema_version };
    my $err = $@;

    like($err, qr/schema_class is not defined/, "Throws error when nested class is missing");
};

done_testing;
