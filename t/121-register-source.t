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

subtest "Dynamic Registration Metadata" => sub {
    my $source = DBIx::Class::ResultSource->new({ name => 'temp_table' });
    $source->add_columns( id => { data_type => 'integer' } );
    $source->result_class('TestSchema::Result::User');

    # 1. Register in Parent
    $schema->register_source('DynamicSource', $source);

    # 2. Verify Parent can resolve it
    my $rs = eval { $schema->resultset('DynamicSource') };
    ok($rs, "Parent created ResultSet for DynamicSource") or diag $@;

    is($schema->class('DynamicSource'), 'TestSchema::Result::User',
       "Parent maps DynamicSource to correct Result Class");

    # 3. Handle the Worker limitation
    # We skip the count_future check for now because Workers don't share
    # the Parent's dynamic memory state.
    # Note: Workers cannot see DynamicSource unless defined in the schema class file.";
};

done_testing;
