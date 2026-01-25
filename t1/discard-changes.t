
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

my $base_schema = TestSchema->connect($dsn);
$base_schema->deploy();
$base_schema->resultset('User')->create({
    id    => 1,
    name  => 'Initial User',
    email => 'test@test.com'
});

# 2. Initialize the Async Engine
my $loop = IO::Async::Loop->new;
my $async_schema = DBIx::Class::Async::Schema->connect($dsn, {
    schema_class => 'TestSchema',
    async_loop   => $loop,
    workers      => 2,
});

subtest 'Row: discard_changes' => sub {
    # 1. Setup: Create a user and fetch it via the Async Row
    my $id = 100;
    $base_schema->resultset('User')->create({
        id    => $id,
        name  => 'Original Name',
        email => 'old@test.com'
    });

    my $row = $async_schema->resultset('User')->find($id)->get;
    is($row->name, 'Original Name', 'Row loaded with original name');

    # 2. Simulate an external database change (out-of-band)
    $base_schema->resultset('User')->find($id)->update({
        name => 'New Remote Name'
    });

    # 3. Verify the local row is now stale
    is($row->name, 'Original Name', 'Local row is still stale');

    # 4. Make a local change to test dirty flag clearing
    $row->email('temporary@change.com');
    ok($row->{_dirty}{email}, 'Row is locally dirty before discard');

    # 5. Perform the discard_changes
    my $f = $row->discard_changes();
    isa_ok($f, 'Future', 'discard_changes returns a Future');

    my $returned_row = $f->get;

    # 6. Final Verifications
    is($returned_row, $row, 'Returns self on success');
    is($row->name, 'New Remote Name', 'Name refreshed from database');
    is($row->email, 'old@test.com', 'Local dirty changes were reverted');
    is_deeply($row->{_dirty}, {}, 'Dirty flags were cleared');
};

done_testing();
