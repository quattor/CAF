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

done_testing();
