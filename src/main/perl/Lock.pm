#${PMpre} CAF::Lock${PMpost}

use CAF::Object;
use CAF::Reporter;

use LC::Exception qw(SUCCESS throw_error);
use FileHandle;
use Fcntl qw(:flock);

use Exporter;
use vars qw(@ISA @EXPORT @EXPORT_OK);

@ISA = qw(CAF::Reporter CAF::Object Exporter);

@EXPORT_OK = qw(FORCE_NONE FORCE_ALWAYS FORCE_IF_STALE);


use constant FORCE_NONE     => 0;
use constant FORCE_ALWAYS   => 1;
use constant FORCE_IF_STALE => 2;  # for backwards compatibility only
                                   # has no effect now


=pod

=head1 NAME

CAF::Lock - Class for handling application instance locking

=head1 SYNOPSIS

    use CAF::Lock;

    $lock = CAF::Lock->new('/var/lock/quattor/spma');

    unless ($lock->set_lock()) {...}
    unless ($lock->set_lock(10, 2) {...}
    unless ($lock->set_lock(3, 3, FORCE_ALWAYS)) {...}

    unless ($lock->unlock()) {....}

=head1 INHERITANCE

    CAF::Reporter

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
    $timeout = 0 unless (defined $retries);

    if ($self->{LOCK_SET}) {
        # oops.
        $self->error("lock already set by this application instance: $self->{LOCK_FILE}");
        return;
    }

    my $tries = 0;
    do {
        if ($tries > 0) {
            $self->verbose("lock file is already held, try $tries out of $retries");
            sleep($timeout);
        }
        $tries++;
        return SUCCESS if $self->_try_lock($force);
    } while ($tries < $retries && $timeout);

    $self->error("cannot acquire lock after $tries tries: $self->{LOCK_FILE}");
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
            $self->error("cannot close lock file: $self->{LOCK_FILE}")
                unless $self->{LOCK_FH}->close();
        }
        $self->{LOCK_SET} = undef;
        $self->{LOCK_FH} = undef;
    } else {
        $self->error("lock not held by this application instance: $self->{LOCK_FILE}, not unlocking");
        return;
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

=cut

sub _initialize
{
    my ($self, $lockfilename) = @_;

    $self->{LOCK_SET} = undef;
    $self->{LOCK_FILE} = $lockfilename;

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

    my $lf = FileHandle->new("> $self->{LOCK_FILE}");
    unless ($lf) {
        $self->error("cannot create lock file: $self->{LOCK_FILE}");
        return;
    }
    unless (flock($lf, LOCK_EX|LOCK_NB)) {
        # Could not get the lock
        return unless (defined($force) && $force == FORCE_ALWAYS);

        # In force mode, continue but don't save the filehandle
        $lf->close();
        $lf = undef;
    }

    $self->{LOCK_FH} = $lf;
    $self->{LOCK_SET} = 1;

    return SUCCESS;
}

=pod

=back

=cut

1; ## END ##
