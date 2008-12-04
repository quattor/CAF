
use strict;

BEGIN {
	unshift (our @INC, qw(.. ../../perl-LC));
}

use CAF::Lock qw(FORCE_IF_STALE FORCE_ALWAYS);
 
my $lock=CAF::Lock->new("/tmp/lock-caf");


print "locked at start\n" if ($lock->is_locked());

my $lockpid=$lock->get_lock_pid();

print "lockpid : $lockpid\n" if ($lockpid);


print "is stale\n" if ($lock->is_stale);

print "now locking myself... with ALWAYS\n";
unless ($lock->set_lock()) { #3,3,FORCE_ALWAYS)) {
	print "cannot set lock\n";
}

print "locked\n" if ($lock->is_locked());
                                                                                
unless ($lock->unlock()) {
	print "cannot release lock\n";
}
 

