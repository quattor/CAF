use strict;
use warnings;
use Test::More tests => 7;
use CAF::Lock qw(FORCE_IF_STALE FORCE_ALWAYS);

my $lock=CAF::Lock->new("/tmp/lock-caf");

ok(!$lock->is_locked(), "Unlocked at start");
my $lockpid=$lock->get_lock_pid();

is($lockpid, undef, "Lock PID undefined on unaquired lock");

ok($lock->set_lock(), "Lock set");
ok($lock->is_locked(), "Locked on request");

is($lock->get_lock_pid(), $$, "Lock PID correctly set on locked object");

ok($lock->is_stale(), "Lock is stale");

ok($lock->unlock(), "Lock released");

