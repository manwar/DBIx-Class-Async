
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

# Initialize and seed the DB so all_future has something to find
my $base_schema = TestSchema->connect($dsn);
$base_schema->deploy();
$base_schema->resultset('User')->create({
    id    => 1,
    name  => 'BottomUp User',
    email => 'bu@test.com'
});

# 2. Initialize the Async Engine
my $loop = IO::Async::Loop->new;
my $async_schema = DBIx::Class::Async::Schema->connect($dsn, {
    schema_class => 'TestSchema',
    async_loop   => $loop,
    workers      => 2,
});

subtest 'ResultSet find() - Success' => sub {
    my $rs = $async_schema->resultset('User');

    # 1. Setup
    my $name = "Finder";
    my $created = $rs->create({ name => $name, email => 'find@test.com' })->get;
    my $id = $created->id;

    # 2. Test find by Primary Key
    my $user = $rs->find($id)->get;

    isa_ok($user, 'DBIx::Class::Async::Row', 'find() returns a Row object');
    is($user->id, $id, 'Found the correct ID');
    is($user->name, $name, 'Data is intact');
};

subtest 'ResultSet find() - No result' => sub {
    my $rs = $async_schema->resultset('User');

    # Use an ID that definitely doesn't exist
    my $user = $rs->find(999_999_999)->get;

    is($user, undef, 'find() returns undef for non-existent record');
};

subtest 'The Chain: find()->then(delete)' => sub {
    my $rs = $async_schema->resultset('User');
    my $temp_user = $rs->create({ name => 'To Be Deleted' })->get;
    my $id = $temp_user->id;

    # The exact use case you requested
    my $future = $rs->find($id)->then(sub {
        my $user = shift;

        return Future->done(0) unless $user; # Guard against undef
        return $user->delete;
    });

    my $deleted_count = $future->get;
    is($deleted_count + 0, 1, 'Chain successfully deleted the row');

    # Verify it's gone
    my $gone = $rs->find($id)->get;
    is($gone, undef, 'Confirmed: Record is no longer in DB');
};



done_testing();
