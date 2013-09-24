# -*- mode: cperl -*-
use strict;
use warnings;
use Test::More;
use CAF::Lock qw(FORCE_IF_STALE FORCE_ALWAYS);
use Test::MockObject::Extends;

use constant LOCK_TEST_DIR => "target/tests";
use constant LOCK_TEST => LOCK_TEST_DIR . "/lock-fork";

eval {
    $$++;
    $$--;
};
plan skip_all => "Cannot manipulate PID" if $@;
my $pid;

my $mock = Test::MockObject::Extends->new("CAF::Lock");

$mock->mock('unlock', 1);

mkdir(LOCK_TEST_DIR);
unlink(LOCK_TEST);

my $lock=CAF::Lock->new(LOCK_TEST);

$lock->set_lock();

$lock=CAF::Lock->new(LOCK_TEST);

$$++;

$lock = undef;

$mock->next_call();
is($mock->next_call(), undef, "Lock is not released after forking");

done_testing();
