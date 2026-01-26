
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

# 1. Setup real temporary SQLite database
my ($fh, $filename) = tempfile(SUFFIX => '.db', UNLINK => 1);
my $dsn = "dbi:SQLite:dbname=$filename";

TestSchema->connect($dsn)->deploy();

my $loop = IO::Async::Loop->new;
my $async_schema = DBIx::Class::Async::Schema->connect($dsn, {
    schema_class => 'TestSchema',
    async_loop   => $loop,
    workers      => 2,
});

my $rs = $async_schema->resultset('User');

subtest 'Standard Populate' => sub {
    my $f = $async_schema->resultset('User')->populate([
        [qw/name age/],
        ['Dave', 50],
        ['Eve', 25]
    ]);

    # Use the helper we defined above
    my $res = wait_for($f);

    is(ref $res, 'ARRAY', "Returns array of rows");
    is(scalar @$res, 2, "Got 2 rows back");
    is($res->[0]{name}, 'Dave', "Dave is here");

    done_testing(); # Marks the subtest as finished
};

subtest 'Bulk Populate' => sub {
    my $f = $async_schema->resultset('User')->populate_bulk([
        { name => 'Frank', age => 28 }
    ]);

    my $res = wait_for($f);

    ok($res, "Bulk returns truthy success");
    done_testing();
};

done_testing(); # Marks the whole script as finished

sub wait_for {
    my $f = shift;
    my $result;
    $f->on_ready(sub {
        my $f = shift;
        $result = $f->is_done ? $f->result : undef;
        $loop->stop;
    });
    $loop->run;
    return $result;
}

