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

ok($lock->set_lock(), "Lock set");
ok($lock->is_locked(), "Locked on request");

ok($lock->unlock(), "Lock released");

done_testing();
