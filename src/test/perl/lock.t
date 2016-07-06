# -*- mode: cperl -*-
use strict;
use warnings;
use Test::More;
use Test::Quattor::Object;
use Test::MockModule;
use CAF::Lock qw(FORCE_ALWAYS FORCE_NONE FORCE_IF_STALE);

use constant LOCK_TEST_DIR => "target/tests";
use constant LOCK_TEST => LOCK_TEST_DIR . "/lock-caf";

my $obj = Test::Quattor::Object->new();

=head1 regular usage

=cut

mkdir(LOCK_TEST_DIR);
unlink(LOCK_TEST);

my $lock1 = CAF::Lock->new(LOCK_TEST, log => $obj);
my $lock2 = CAF::Lock->new(LOCK_TEST, log => $obj);

ok(!$lock1->is_set(), "lock1 unlocked at start");
ok(!$lock2->is_set(), "lock2 unlocked at start");

ok($lock2->unlock(), "lock2 lock released (while lock2 unlocked)");
ok(!$lock2->is_set(), "lock2 still unlocked after unlock while unlocked");

ok($lock1->set_lock(), "lock1 lock set");
ok($lock1->is_set(), "lock1 locked on request");
ok(!$lock2->is_set(), "lock2 unlocked when lock1 locked");

ok($lock1->set_lock(), "lock1 set on when lock1 already taken");

ok(!$lock2->set_lock(), "lock2 not set when lock1 locked");
ok(!$lock2->is_set(), "lock2 failed set still unlocked when lock1 locked");

ok($lock1->unlock(), "lock1 lock released");
ok(!$lock1->is_set(), "lock1 unlocked when lock1 unlocked");
ok(!$lock2->is_set(), "lock2 unlocked when lock1 unlocked");

ok($lock1->unlock(), "lock1 lock released while lock1 already released");

ok($lock2->set_lock(), "lock2 set when lock1 unlocked");
ok($lock2->is_set(), "lock2 locked on request");
ok(!$lock1->is_set(), "lock1 unlocked when lock2 unlocked");


=head1 oldtsyle compatibility tests

=cut


sub makefile
{
    my $fn = shift;
    open(FH, ">$fn");
    my $txt = shift;
    print FH (defined($txt) ? $txt : "ok");
    close(FH);
}

sub readfile
{
    open(FH, shift);
    my $txt = join('', <FH>);
    close(FH);
    return $txt;
}

# Make oldstyle non-stale lock
$lock1 = undef;
unlink(LOCK_TEST);

my $pid = 0;
ok(kill(0, $pid), "PID $pid exists");
makefile(LOCK_TEST, "$pid");

$lock1 = CAF::Lock->new(LOCK_TEST, log => $obj);
ok($lock1->_is_locked_oldstyle(),
   "Presence of non-empty lockfile is an old-style lock (by other process) and pid exists");
ok(! $lock1->_is_locked_oldstyle(FORCE_ALWAYS),
   "Presence of non-empty lockfile is not an old-style lock (by other process) if FORCE_ALWAYS is used and pid exists");
ok($lock1->_is_locked_oldstyle(FORCE_IF_STALE),
   "Presence of non-empty lockfile is an old-style lock if FORCE_IF_STALE is used and pid exists");

# Make oldstyle stale lock
$lock1 = undef;
unlink(LOCK_TEST);

# will take a while till this becomes a possible PID;
# should also not be too big so that perl still thinks this is an interger
$pid = 2**31;
like("$pid", qr{^\d+$}, "too high pid $pid should still be integer");
ok(! kill(0, "$pid"), "no such PID $pid");
makefile(LOCK_TEST, "$pid");

$lock1 = CAF::Lock->new(LOCK_TEST, log => $obj);
ok($lock1->_is_locked_oldstyle(),
   "Presence of non-empty lockfile is an old-style lock (by other process) and stale pid");
ok(! $lock1->_is_locked_oldstyle(FORCE_ALWAYS),
   "Presence of non-empty lockfile is not an old-style lock (by other process) if FORCE_ALWAYS is used and stale pid");
ok(! $lock1->_is_locked_oldstyle(FORCE_IF_STALE),
   "Presence of non-empty lockfile is not an old-style lock if FORCE_IF_STALE is used and stale pid");

# Test FORCE_IF_STALE flag used to take a lock
# when a an old-style lock file is present
# but the pid which created it no longer exists
ok(! $lock1->set_lock(), "no lock taken on stale PID without FORCE_IF_STALE");
ok($lock1->set_lock(0, 0, FORCE_IF_STALE), "lock taken on stale PID with FORCE_IF_STALE");
ok($lock1->unlock(), "lock released with stale PID");

# after old-style lock was taken and released,
# it shouldn't be an oldstyle lock anymore
ok(! $lock1->_is_locked_oldstyle(),
   "old-style lock is not an old-style lock anymore after lock-unlock");

ok(-f LOCK_TEST, "lockfile exists after lock-unlock");
is(readfile(LOCK_TEST), '', 'lockfile is empty after lock-unlock');


=head1 oldstyle reporter tests

=cut

$lock1 = undef;
unlink(LOCK_TEST);
my $mock = Test::MockModule->new('CAF::Reporter');
my $error = 0;
$mock->mock('error', sub {shift; $error+=1; return 1;});
# Do not pass log instance for this test
$lock1 = CAF::Lock->new(LOCK_TEST);
ok($lock1->error("test"), "mocked error method returned success");
is($error, 1, "mocked error counter");

done_testing();
