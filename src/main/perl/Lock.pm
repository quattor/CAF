#${PMpre} CAF::Lock${PMpost}

use CAF::Object qw(SUCCESS);
use FileHandle;
use File::stat; # overrides builtin stat
use Fcntl qw(:flock);

# Only required to support legacy CAF::Reporter inheritance
# Make sure nothing gets imported
use CAF::Reporter qw();
our @ISA;

use parent qw(CAF::Object Exporter);

our @EXPORT_OK = qw(FORCE_NONE FORCE_ALWAYS FORCE_IF_STALE);


use constant FORCE_NONE     => 0;
use constant FORCE_ALWAYS   => 1;
# for backwards compatibility only
# has no effect on newly created locks
use constant FORCE_IF_STALE => 2;

=pod

=head1 NAME

CAF::Lock - Class for handling application instance locking

=head1 SYNOPSIS

    use CAF::Lock;

    $lock = CAF::Lock->new('/var/lock/quattor/spma', log => $reporter);

    unless ($lock->set_lock()) {...}
    unless ($lock->set_lock(10, 2) {...}
    unless ($lock->set_lock(3, 3, FORCE_ALWAYS)) {...}

    unless ($lock->unlock()) {....}

=head1 INHERITANCE

    CAF::Object

=head1 DESCRIPTION

The B<CAF::Lock> class provides methods for handling application locking.

=head1 PUBLIC METHODS

=over 4

=item set_lock(I<retries>, I<timeout>, I<force>)

Tries I<retries> times to set the lock.  If I<force> is set to B<FORCE_NONE>
or not defined and the lock is set, it sleeps for I<timeout>.  Returns
B<SUCCESS>, or B<undef> on failure.

If I<retries> or I<timeout> are not defined or set to 0, only a single
attempt is done to acquire the lock.

If I<force> is set to B<FORCE_ALWAYS> then the lock file is just set
again, even if the lock is already set by another application
instance, and neither I<timeout> nor I<retries> are taken
into account.

=cut

sub set_lock
{
    my ($self, $retries, $timeout, $force) = @_;

    $retries = 0 unless (defined $retries);
    $timeout = 0 unless (defined $timeout);

    if ($self->{LOCK_SET}) {
        $self->warn("lock already set by this application instance: $self->{LOCK_FILE}");
        return SUCCESS;
    }

    my $tries = 0;
    do {
        if ($tries > 0) {
            $self->verbose("lock file is already held, try $tries out of $retries (timeout $timeout)");
            sleep($timeout);
        }
        $tries++;
        return SUCCESS if $self->_try_lock($force);
    } while ($tries <= $retries && $timeout);

    $self->error("cannot acquire lock after $tries tries (timeout $timeout): $self->{LOCK_FILE}");
    return;
}

=item unlock()

Releases the lock and returns B<SUCCESS>.  Reports an error and returns
B<undef> if the lock cannot be released.  If the object (application
instance) does not hold the lock, an error is reported and B<undef>
is returned.

=cut

sub unlock
{
    my $self = shift;
    if ($self->{LOCK_SET}) {
        # if we forced the lock LOCK_FH can be undef

        if ($self->{LOCK_FH}) {
            unless (flock($self->{LOCK_FH}, LOCK_UN)) {
                $self->error("cannot release lock: $self->{LOCK_FILE}");
                return;
            }
            # close the filehandle, clearing any previous content
            unless ($self->{LOCK_FH}->close()) {
                $self->error("cannot close lock file: $self->{LOCK_FILE}");
            }
        }

        $self->{LOCK_SET} = undef;
        $self->{LOCK_FH} = undef;

    } else {
        $self->warn("lock not held by this application instance: $self->{LOCK_FILE}, nothing to unlock");
    }
    return SUCCESS;
}


=item is_set()

Returns B<SUCCESS> if lock is set by application instance, B<undef> otherwise.

=cut

sub is_set
{
    my $self = shift;
    return $self->{LOCK_SET} ? SUCCESS : ();
}

=back

=head1 PRIVATE METHODS

=over 4

=item _initialize(I<lockfilename>)

Initialize the object.  Called by new(I<lockfilename>).

Optional arguments

=over

=item C<log>

A C<CAF::Reporter> object to log to.

=back

=cut

sub _initialize
{
    my ($self, $lockfilename, %opts) = @_;

    $self->{LOCK_SET} = undef;
    $self->{LOCK_FILE} = $lockfilename;

    # This is intended to move away from some legacy code
    # Do not copy this ever somewhere else
    # Use: $self->{log} = $opts{log} if $opts{log};
    if ($opts{log}) {
        $self->{log} = $opts{log};
    } else {
        unshift(@ISA, 'CAF::Reporter');
    }

    return SUCCESS;
}


=item _try_lock(I<force>)

Called by set_lock() to create the lock file and return B<SUCCESS> if we were
able to flock() the file.

If I<force> is set to B<FORCE_ALWAYS> then this method will return B<SUCCESS>
even if flock() was unsuccessful.

=cut

sub _try_lock
{
    my ($self, $force) = @_;

    $force = FORCE_NONE if ! defined($force);

    my $lf;

    # has_lock: does the current instance have the lock?
    my $has_lock = 1;

    if ($self->_is_locked_oldstyle($force)) {
        # Do not bother try to take the lock
        $self->warn("Old style lock found $self->{LOCK_FILE}");
        $has_lock = 0;
    } else {
        $lf = FileHandle->new("> $self->{LOCK_FILE}");
        unless ($lf) {
            $self->error("cannot create lock file: $self->{LOCK_FILE}");
            return;
        }
        $has_lock = flock($lf, LOCK_EX|LOCK_NB);
        $self->debug(3, "flock on $self->{LOCK_FILE} gave has_lock $has_lock");
    }

    unless ($has_lock) {
        # Could not get the lock
        # In force mode, continue but don't save the filehandle

        # So always close the $fh if defined
        if(defined($lf)) {
            $lf->close();
            $lf = undef;
        }

        return unless ($force == FORCE_ALWAYS);
    }

    $self->{LOCK_FH} = $lf;
    $self->{LOCK_SET} = 1;

    return SUCCESS;
}


# Before CAF PR#132, CAF::Lock used the presence of the lock file as
# condition to determine if the lock was taken or not.
# The file would hold the PID of the process that had the lock
# (and unlock simply removed the file).
# This method provides support for the existence of an old-style lockfile
# held by another process using old-style locking code.
# It does not modify/cleanup the old-style file (even if it is stale).
# Returns boolean true if the lock has been taken by another process
# (i.e. if it is locked by another old-style instance).
sub _is_locked_oldstyle
{
    my ($self, $force) = @_;

    my $other_has_lock = 0;

    my $st = stat($self->{LOCK_FILE});

    if (! $st) {
        # No file -> no lock
        $self->debug(3, "No lockfile $self->{LOCK_FILE} found: no lock");
    } elsif ($st->size == 0) {
        # Empty file -> no old-style lock due to missing PID in file
        # New-style lockfiles are empty files
        $self->debug(3, "Empty lockfile $self->{LOCK_FILE} found: no old-style lock");
    } else {
        # A non-empty file was found, could be an old-style lock
        $force = FORCE_NONE if ! defined($force);

        if ($force == FORCE_ALWAYS) {
            # No lock, do not even check
            # Will trigger an new-style lock
            $self->debug(3, "_is_locked_oldstyle with FORCE_ALWAYS: pretend there is no lock");
        } elsif ($force == FORCE_IF_STALE) {
            # This is more or less the old get_lock_pid / if_stale method code
            my $fh = FileHandle->new("< " . $self->{'LOCK_FILE'});
            if ($fh) {
                my $pid = $fh->getline();
                $pid = '' if ! defined($pid);

                $fh->close();
                if ($pid =~ m/^(\d+)$/) {
                    # If pid can be signalled, there is a lock by another process
                    $self->debug(3, "_is_locked_oldstyle checking possibly stale PID $1");
                    $other_has_lock = kill(0, $1);
                }
            }
            $self->debug(3, "_is_locked_oldstyle with FORCE_IF_STALE: there is ".($other_has_lock ? 'a': 'no')." lock");
        } else {
            $self->debug(3, "_is_locked_oldstyle file found and force not set: there is a lock");
            $other_has_lock = 1;
        }
    }

    return $other_has_lock;
}

=pod

=back

=cut

1; ## END ##
