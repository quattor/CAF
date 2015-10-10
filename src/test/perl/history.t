use strict;
use warnings;

use FindBin qw($Bin);
use lib "$Bin/modules";

use Test::More;
use Test::MockModule;
use LC::Exception qw (SUCCESS);
use myhistory;
use object_ok;

use CAF::History qw($IDX $ID $TS $REF);

use Scalar::Util qw(refaddr);
use Readonly;

Readonly my $HISTORY => 'HISTORY';

Readonly my $EVENTS => 'EVENTS';
Readonly my $LAST => 'LAST';
Readonly my $NEXTIDX => 'NEXTIDX';
Readonly my $INSTANCES => 'INSTANCES';


my $mockh = Test::MockModule->new('CAF::History');
my $mocko = Test::MockModule->new('object_ok');

my $obj_close = 0;
my $obj_destroy = 0;
$mocko->mock('close', sub {$obj_close++;});
$mocko->mock('DESTROY', sub {$obj_destroy++;});


is($IDX, 'IDX', "exported IDX");
is($ID, 'ID', "exported ID");
is($TS, 'TS', "exported TS");
is($REF, 'REF', "exported REF");

=pod

=head2 not initialized

=cut

my $h0 = myhistory->new();

isa_ok($h0, 'myhistory', 'h is a myhistory instance');
isa_ok($h0, 'CAF::History', 'h is a CAF::History subclass');

ok(! defined($h0->{$HISTORY}), "init_history was not called");

ok($h0->event('wassup'), "Can call event method without issues");
ok(! defined($h0->{$HISTORY}), "without initialised history, nothing is tracked");

=head2 initialize

Test initialisation via init_history

=cut

my $h = myhistory->new(1);
isa_ok($h, 'myhistory', 'h is a myhistory instance');
isa_ok($h, 'CAF::History', 'h is a CAF::History subclass');

is_deeply($h->{$HISTORY}, {
    $EVENTS => [],
    $LAST => {},
    $NEXTIDX => 0,
}, "HISTORY attr initialized correct (no INSTANCES by default)");

=head2 _now

Test _now, time() has 1 sec precision

=cut

ok( (- $h->_now() + time()) <= 1, "_now uses time");

my $now = 0;
$mockh->mock('_now', sub {$now++; return $now;});

is( $h->_now(), 1, "_now uses mocked time");

=head2 no instances

test event tracks no instances

=cut

my $isa = 'object_ok';

my $obj = object_ok->new();
my $oid = "$isa ".refaddr($obj);
isa_ok($obj, $isa, 'obj is a object_ok instance');

$h->event($obj, reason => 'simple test');
is_deeply($h->{$HISTORY}->{$EVENTS}, [
    {
        $IDX => 0,
        $ID => $oid,
        $REF => $isa,
        $TS => 2,
        reason => 'simple test',
    },
], "event added as expected");
ok(! defined($h->{$HISTORY}->{$INSTANCES}),
   'No INSTANCES tracked after adding non-scalar');



$obj = undef;
is($obj_close, 0, 'obj close not called');
is($obj_destroy, 1, 'obj DESTROY called (no references held)');


=head2  test event with instances

2nd argument of myhistory is passed to init_history

=cut

# new obj and oid
$obj = object_ok->new();
$oid = "$isa ".refaddr($obj);
isa_ok($obj, $isa, 'obj is a object_ok instance');

my $h2 = myhistory->new(1, 1);
isa_ok($h2, 'myhistory', 'h2 is a myhistory instance');

is_deeply($h2->{$HISTORY}, {
    $EVENTS => [],
    $LAST => {},
    $NEXTIDX => 0,
    $INSTANCES => {},
}, "h2 HISTORY attr initialized correct (INSTANCES enabled)");

# Why would you pass a hashref?
my $href = {a=>1};
my $hid = "HASH ".refaddr($href);

$h2->event('string', type => 'scalar');
$h2->event($href, type => 'hashref');
$h2->event($obj, type => 'instance');
$h2->event($obj, something => 'else');

is_deeply($h2->{$HISTORY}->{$EVENTS}, [
    {
        $IDX => 0,
        $ID => " string",
        $REF => '',
        $TS => 3,
        type => 'scalar',
    },
    {
        $IDX => 1,
        $ID => $hid,
        $REF => 'HASH',
        $TS => 4,
        type => 'hashref',
    },
    {
        $IDX => 2,
        $ID => $oid,
        $REF => $isa,
        $TS => 5,
        type => 'instance',
    },
    {
        $IDX => 3,
        $ID => $oid,
        $REF => $isa,
        $TS => 6,
        something => 'else',
    },
], "Correct h2 history of events");

is_deeply($h2->{$HISTORY}->{$LAST}, {
    " string" => $h2->{$HISTORY}->{$EVENTS}->[0],
    $hid => $h2->{$HISTORY}->{$EVENTS}->[1],
    $oid => $h2->{$HISTORY}->{$EVENTS}->[3],
}, "Correct h2 LAST events");

is_deeply($h2->{$HISTORY}->{$INSTANCES}, {
    $oid => $obj,
}, "h2 INSTANCES tracks (blessed) obj instance (and not the non-blessed hashref)");

=head2 query_raw

Test the query methods

=cut

# Test match: return anything older than 5 or scalar.
my $match = sub {
    my $ev = shift;

    diag "match event input ",explain $ev;

    return 1 if ($ev->{$TS} > 5);
    return 1 if (! $ev->{$REF});
};

# Test without filter
my $ans = $h2->query_raw($match);
diag "no filter ", explain $ans;
is_deeply($ans, [
    {
        $IDX => 0,
        $ID => " string",
        $REF => '',
        $TS => 3,
        type => 'scalar',
    },
    {
        $IDX => 3,
        $ID => $oid,
        $REF => $isa,
        $TS => 6,
        something => 'else',
    },
], "queried events");

# shallow copy
is($ans->[0]->{$ID}, $h2->{$HISTORY}->{$EVENTS}->[0]->{$ID},
   "corresponding events (w/o filter)");
$ans->[0]->{$ID} = 'woohoo';
is($h2->{$HISTORY}->{$EVENTS}->[0]->{$ID}, " string",
   'query_raw returned shallow copy (w/o filter)');


# with filter
$ans = $h2->query_raw($match, [$ID, 'type', 'something']);
diag "with filter ", explain $ans;
is_deeply($ans, [
    {
        $ID => " string",
        type => 'scalar',
    },
    {
        $ID => $oid,
        something => 'else',
    },
], "queried events with filter on ID, type and something");

# shallow copy
is($ans->[0]->{$ID}, $h2->{$HISTORY}->{$EVENTS}->[0]->{$ID},
   "corresponding events (with filter)");
$ans->[0]->{$ID} = 'woohoo';
is($h2->{$HISTORY}->{$EVENTS}->[0]->{$ID}, " string",
   'query_raw returned shallow copy (with filter)');

=head2 close

close h2, should trigger cleanup of obj

=cut

$obj_close = 0;
$obj_destroy = 0;

$obj = undef;
is($obj_close, 0, 'h2: obj close not called');
is($obj_destroy, 0, 'h2: obj DESTROY not called (reference held in INSTANCES)');


$h2->_cleanup_instances();
ok(! defined($h2->{$HISTORY}->{$INSTANCES}), "INSTANCES cleaned up");
is($obj_close, 1, "h2: instance obj close called");
is($obj_destroy, 1, 'h2: obj DESTROY called');

my $cleanup = 0;
$mockh->mock('_cleanup_instances', sub {$cleanup++;});

$h2->close();

is($cleanup, 1, "h2 close calls _cleanup_instances");
ok(! defined($h2->{$HISTORY}), 'h2 HISTORY attribute cleaned up on close');

$h2->close();
is($cleanup, 1, "h2 close on already closed history does not call _cleanup_instances");

done_testing;
