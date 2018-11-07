#${PMpre} CAF::Log${PMpost}

use parent qw(CAF::Object Exporter);

use LC::Exception qw (SUCCESS throw_error);
use FileHandle;
use Readonly;

Readonly our $SYSLOG => 'SYSLOG';
Readonly our $FH => 'FH';
Readonly our $FILENAME => 'FILENAME';
Readonly my $TSTAMP => 'TSTAMP';
# variable $PID exists when using 'use English;' (and it is $$)
Readonly my $PROCID => 'PROCID';
Readonly my $OPTS => 'OPTS';

our @EXPORT_OK = qw($FILENAME $FH $SYSLOG);

# $FH is used during DESTROY (and close), but might be
# destroyed itself e.g. during global cleanup
my $_FH = $FH;

my $ec = LC::Exception::Context->new->will_store_all;

# TODO: the pod used to say: INHERITANCE: CAF::Reporter

=pod

=head1 NAME

CAF::Log - Simple class for handling log files

=head1 SYNOPSIS


  use CAF::Log;

  my $log = CAF::Log->new('/foo/bar', 'at');

  $log->print("this goes to the log file\n");
  $log->close();

=head1 DESCRIPTION

The B<CAF::Log> class allows to instantiate objects for writing log files.
A log file line can be prefixed by a time stamp.

=head2 Public methods

=over 4

=item C<close()>: boolean

closes the log file, returns SUCCESS on success, undef otherwise
(if no FH attribute exists).

=cut

# Called during DESTROY, use $_XYZ flavour
sub close
{
    my $self = shift;

    return unless (defined $self->{$_FH});

    $self->{$_FH}->close();
    $self->{$_FH} = undef;

    return SUCCESS;
}

=pod

=item C<print($msg)>: boolean

Prints C<$msg> into the log file.

If C<PROCID> attribute is defined (value is irrelevant),
the proces id in square brackets (C<[PID]>) and additional
space are prepended.

If C<TSTAMP> attribute is defined (value is irrelevant),
a C<YYYY/MM/DD-HH:mm:ss> timestamp and additional space
are prepended.

No newline is added to the message.

Returns the return value of invocation of FH print method.

=cut

# TODO: use 'if ($self->{$TSTAMP})' (and PROCID) rather than only checking if defined

sub print
{
    my ($self, $msg) = @_;

    if (defined $self->{$PROCID}) {
        $msg = "[$$] $msg";
    };

    if (defined $self->{$TSTAMP}) {
        # print timestamp the SUE way ;-)
        my ($sec, $min, $hour, $mday, $mon, $year) = localtime(time);
        $msg = sprintf("%04d/%02d/%02d-%02d:%02d:%02d %s",
                       $year+1900, $mon+1, $mday, $hour, $min, $sec, $msg);
    };

    return $self->{$FH}->print($msg);
}


=pod

=back

=head2 Private methods

=over 4

=item C<_initialize($filename, $options)>

C<$options> is a string with magic letters

=over

=item a: append to a logfile

=item w: truncate a logfile

=item t: generate a timestamp on every print

=item p: add PID

=back

Only one of C<w> or C<a> can and has to be set. (There is no default.)

If the C<w> option is used and there was a previous
log file, it is renamed with the extension '.prev'.

Examples:

    CAF::Log->new('/foo/bar', 'at'): append, enable timestamp
    CAF::Log->new('/foo/bar', 'w') : truncate logfile, no timestamp

If the filename ends with C<.log>, the C<SYSLOG> attribute is set to
basename of the file without suffix (relevant for C<CAF::Reporter::syslog>).

=cut

sub _initialize
{
    my ($self, $filename, $options) = @_;

    $self->{$FILENAME} = $filename;
    $self->{$OPTS} = $options;

    if ($self->{$FILENAME} =~ m{([^/]*)\.log$}) {
        $self->{$SYSLOG} = $1;
    }

    unless ($self->{$OPTS} =~ /^[tp]*[wa][tp]*$/) {
        throw_error("Bad options for log ".$self->{$FILENAME}.
                    ": ".$self->{$OPTS});
        return;
    }

    my %opts = map { $_ => 1 } split( '', $self->{$OPTS});

    $self->{$TSTAMP} = $opts{t};
    $self->{$PROCID} = $opts{p};

    my ($fhmode, $msg);
    if ($opts{w}) {
        # Move old filename away if mode is 'w'.
        rename ($self->{$FILENAME}, $self->{$FILENAME}.'.prev')
            if (-e $self->{$FILENAME});
        $fhmode = ">";
        $msg = "write";
    } else {
        # setting is 'a': append to (potentially existing) file
        $fhmode = ">>";
        $msg = "append";
    }

    unless ($self->{$FH} = FileHandle->new("$fhmode ".$self->{$FILENAME})) {
        throw_error("Open for $msg " . $self->{$FILENAME} . " $!");
        return;
    }

    # Autoflush on
    $self->{$FH}->autoflush();

    return SUCCESS;
}

=pod

=item DESTROY

Called during garbage collection. Invokes close().

=cut

# All Readonly here (and in methods called) might be
# cleaned up during global cleanup, so use the $_XYZ
# flavours here (and methods called here).
sub DESTROY {
    my $self = shift;
    $self->close() if (defined $self->{$_FH});
}

=pod

=back

=cut

# TODO: these are only send to STDERR, not logged
#       move this to DESTROY?

END {
    # report all stored warnings
    foreach my $warning ($ec->warnings) {
        warn("[WARN] $warning");
    }
    $ec->clear_warnings;
}

1; ## END ##
