# ${license-info}
# ${developer-info}
# ${author-info}
# ${build-info}

package CAF::Lock;

use strict;
use CAF::Object;
use CAF::Reporter;

use LC::Exception qw (SUCCESS throw_error);
use FileHandle;
#use Proc::ProcessTable;

use Exporter;
use vars qw(@ISA @EXPORT @EXPORT_OK);

@ISA = qw(CAF::Reporter CAF::Object Exporter);

@EXPORT_OK = qw(FORCE_ALWAYS FORCE_IF_STALE);


use constant FORCE_NONE => 0;
use constant FORCE_ALWAYS => 1;
use constant FORCE_IF_STALE => 2;


=pod

=head1 NAME

CAF::Lock - Class for handling application instance locking

=head1 SYNOPSIS


  use CAF::Lock;

  $lock=CAF::Lock->new('/var/lock/quattor/spma');

  if ($lock->is_locked()) {...} else {...};

  $lockpid=$lock->get_lock_pid();

  unless ($lock->set_lock()) {...}
  unless ($lock->set_lock(10,2) {...}
  unless ($lock->set_lock(3,3,FORCE_IF_STALE)) {...}

  if ($lock->is_stale()) {...} else {...};

  unless ($lock->unlock()) {....}


=head1 INHERITANCE

  CAF::Reporter

=head1 DESCRIPTION

The B<CAF::Lock> class provides methods for handling application locking.


=over

=cut

#------------------------------------------------------------
#                      Public Methods/Functions
#------------------------------------------------------------

=pod

=back

=head2 Public methods

=over 4

=item is_locked()

If a lock is set for the lock file, returns SUCCESS, undef otherwise.

=cut

sub is_locked() {
  my $self=shift;
  return SUCCESS if (-e $self->{'LOCK_FILE'});
  return undef;
}

=pod

=item get_lock_pid()

Returns the PID file of the application holding the lock, undef if no
lockfile found

=cut

sub get_lock_pid() {
  my $self=shift;

  return undef unless ($self->is_locked());
  return $$ if ($self->{'LOCK_SET'});
  my $lf=FileHandle->new("< " . $self->{'LOCK_FILE'});
  unless ($lf) {
    $self->error("cannot open lock file for read: ".$self->{'LOCK_FILE'});
    return undef;
  }
  my $pid=$lf->getline();
  unless (defined $pid) {
    $self->error("cannot read from lock file: ".$self->{'LOCK_FILE'});
    return undef;
  }
  unless ($lf->close()) {
    $self->error("cannot close lock file: ".$self->{'LOCK_FILE'});
    return undef;
  }
  if ($pid !~ m{^(\d+)$}) {
      $self->error("Strange PID $pid holding lock $self->{LOCK_FILE}");
      return undef;
  }
  return $1;
}


=pod

=item is_stale()

Returns SUCCESS if the lock is stale - a lock file is set but the
corresponding PID does not exist. Returns undef otherwise.

=cut

sub is_stale {
  my $self=shift;

  return undef unless ($self->is_locked());
  my $lock_pid=$self->get_lock_pid();
  if ($lock_pid && kill(0, $lock_pid)) {
      return undef;
  } else {
      return SUCCESS;
  }
}


=pod

=item set_lock ($retries,$timeout,$force);

Tries $retries times to set the lock. If $force is set to FORCE_NONE
or not defined and the lock is set, it sleeps for
rand($timeout). Writes the current PID ($$) into the lock
file. Returns SUCCESS or undef on failure.

If $retries or $timeout are not defined or set to 0, only a single
attempt is done to acquire the lock.

If $force is set to FORCE_ALWAYS then the lockfile is just set
again, independently if the lock is already set by another application
instance.

If $force is set to FORCE_IF_STALE then the lockfile is set if the
application instance holding the lock is dead (PID not alive).

If $force is set to FORCE_ALWAYS, or if $force is defined to
FORCE_IF_STALE and a stale lock file is detected, then neither
$timeout nor $retries are taken into account.

=cut

sub set_lock {
  my ($self,$retries,$timeout,$force)=@_;

  $retries=0 unless (defined $retries);
  $timeout=0 unless (defined $retries);

  if ($self->{LOCK_SET}) {
    # oops.
    $self->error("lock already set by this application instance");
    return undef;
  }

  unless ($force == FORCE_ALWAYS ||
	  ($force == FORCE_IF_STALE && $self->is_stale())) {
    my $tries=1;
    while ($tries <= $retries &&
	   ($self->is_locked() && !($force == FORCE_IF_STALE && $self->is_stale()))) {
      my $sleep=rand($timeout);
      $self->verbose("lockfile is already held, try $tries out of $retries");
      $tries++;
      sleep($sleep);
    }
  }
  if ($self->is_locked() && !($force == FORCE_ALWAYS ||
	  ($force == FORCE_IF_STALE && $self->is_stale()))) {
    $self->error("cannot acquire lock file: ".$self->{'LOCK_FILE'});
    return undef;
  }
  # now got the lock (or forcing!)
  my $lf=FileHandle->new("> " . $self->{'LOCK_FILE'});
  unless ($lf) {
    $self->error("cannot create lock file: ".$self->{'LOCK_FILE'});
    return undef;
  }
  print $lf $$;
  unless ($lf->close()) {
    $self->error("cannot close lock file: ".$self->{'LOCK_FILE'});
    return undef;
  }
  $self->{LOCK_SET}=1;
  return SUCCESS;
}


=pod

=item unlock

Releases the lock and returns SUCCESS. Reports an error and returns
undef if the lock file cannot be released. If the object (application
instance) does not hold the lockfile, an error is reported and undef
is returned.

=cut

sub unlock {
  my $self=shift;
  if ($self->{LOCK_SET}) {
    unless (unlink($self->{'LOCK_FILE'})) {
      $self->error("cannot release lock file: ",$self->{'LOCK_FILE'});
      return undef;
    } else {
      $self->{LOCK_SET}=undef;
    }
  } else {
    $self->error("lock not held by this application instance, not unlocking");
    return undef;
  }
  return SUCCESS;
}


=pod

=item is_set

Returns SUCCESS if lock is set by application instance, undef otherwise

=cut

sub is_set {
  my $self=shift;
  return SUCCESS if ($self->{LOCK_SET});
  return undef;
}



=pod

=back

=head2 Private methods

=over 4

=item _initialize($lockfilename)

initialize the object. Called by new($lockfilename).

=cut

sub _initialize ($$$) {
  my ($self,$lockfilename) = @_;

  $self->{'LOCK_SET'}=undef;
  $self->{'LOCK_FILE'} = $lockfilename;
  return SUCCESS;

}



=pod

=item DESTROY

called during garbage collection. Invokes unlock() if lock is set by
application instance.

=cut


sub DESTROY {
  my $self = shift;
  # We unlock only on the process that owns the lock.  Otherwise this
  # might be a forked process that is exiting and shouldn't sweep
  # under its parent's feet.
  $self->unlock() if $self->{LOCK_SET} && $self->get_lock_pid() == $$;
}


=pod

=back

=cut

1; ## END ##
