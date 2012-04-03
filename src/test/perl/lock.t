# -*- mode: cperl -*-
use strict;
use warnings;
use Test::More;
use CAF::Lock qw(FORCE_IF_STALE FORCE_ALWAYS);

use constant LOCK_TEST_DIR => "target/tests";
use constant LOCK_TEST => LOCK_TEST_DIR . "/lock-caf";

mkdir(LOCK_TEST_DIR);
unlink(LOCK_TEST);

my $lock=CAF::Lock->new(LOCK_TEST);

ok(!$lock->is_locked(), "Unlocked at start");
my $lockpid=$lock->get_lock_pid();

is($lockpid, undef, "Lock PID undefined on unaquired lock");

ok($lock->set_lock(), "Lock set");
ok($lock->is_locked(), "Locked on request");

is($lock->get_lock_pid(), $$, "Lock PID correctly set on locked object");

ok(!$lock->is_stale(), "Lock is NOT stale");

ok($lock->unlock(), "Lock released");

open(my $fh, ">", LOCK_TEST);
if (!kill(0, $$+1)) {
    print $fh $$+1;
    close($fh);
    ok($lock->is_stale(), "Lock by non-existing process is stale");
}

ok(!$lock->set_lock(), "Non-forced lock on stalled lock not acuired");
ok($lock->set_lock(0, 0, FORCE_IF_STALE), "Forced lock on stalled resource aquired");
$lock->unlock();

open($fh, ">", LOCK_TEST);
close($fh);

ok($lock->is_stale(), "Lock on empty lock file is stale");
ok($lock->set_lock(0, 0, FORCE_IF_STALE), "Forced lock on empty lock file aquired");

# How does it handle when an empty lock file is there?



done_testing();
