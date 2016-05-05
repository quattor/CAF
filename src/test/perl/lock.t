# -*- mode: cperl -*-
use strict;
use warnings;
use Test::More;
use CAF::Lock qw(FORCE_ALWAYS);

use constant LOCK_TEST_DIR => "target/tests";
use constant LOCK_TEST => LOCK_TEST_DIR . "/lock-caf";

mkdir(LOCK_TEST_DIR);
unlink(LOCK_TEST);

my $lock1 = CAF::Lock->new(LOCK_TEST);
my $lock2 = CAF::Lock->new(LOCK_TEST);

ok(!$lock1->is_set(), "Unlocked at start");
ok($lock1->set_lock(), "Lock set");
ok($lock1->is_set(), "Locked on request");

ok(!$lock2->set_lock(), "Second lock when file locked");

ok($lock1->unlock(), "Lock released");

ok($lock2->set_lock(), "Second lock when file unlocked");
ok($lock2->is_set(), "Second lock locked on request");

done_testing();
