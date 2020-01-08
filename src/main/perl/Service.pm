#${PMpre} CAF::Service${PMpost}

use CAF::Process;
use LC::Exception qw (SUCCESS);

our $AUTOLOAD;
use parent qw(CAF::Object Exporter);

use Readonly;

Readonly my $DEFAULT_SLEEP => 5;
Readonly::Array our @FLAVOURS => qw(linux_sysv linux_systemd solaris);
Readonly::Array my @GENERATED_ACTIONS => qw(start stop restart reload condrestart);
Readonly::Array our @ALL_ACTIONS => (@GENERATED_ACTIONS, 'stop_sleep_start');

# Mapping the methods we expose here to the svcadm operations. We
# choose the Linux terms for our API.
Readonly::Hash my %SOLARIS_METHODS => {
    start => 'enable',
    stop => 'disable',
    restart => 'restart',
    condrestart => 'restart'
};

our @EXPORT_OK = qw(@FLAVOURS @ALL_ACTIONS os_flavour __make_method);

=pod

=head1 NAME

CAF::Service - Class for starting and stopping daemons in different
platforms

=head1 SYNOPSIS

    use CAF::Service;
    my $srv = CAF::Service->new(['ntpd'], log => $self, %opts);
    $srv->reload();
    $srv->stop();
    $srv->start();
    $srv->restart();
    $srv->condrestart();
    $srv->stop_sleep_start();

Will do the right thing with SystemV Init scripts, Systemd units and
Solaris' C<svcadm>.

=head1 DESCRIPTION

This class abstracts away the differences when operating with Daemons
in different Unixes.

=cut

=head2 Private methods

=over

=item C<_initialize>

Initialize the process object. Arguments:

=over

=item C<$services>

Reference to a list of services to be handled.

=back

It takes some extra optional arguments:

=over

=item C<log>

A C<CAF::Reporter> object to log daemon activities to.

=item C<timeout>

Maximum execution time, in seconds, for any service operations. If
it's too slow it will be killed.  If not defined, the command won't
time out.

On Solaris it implies that C<svcadm> actions are executed
synchronously.  After this timeout, the operation will continue in
background, but will NOT mark the service as failed.  For marking
timed out services operations as failed, we have to edit the method
definition, which is out of the scope of this method.  See the man
page for smf_method for more details.

On systemd-based systems, the timeout parameter is ignored.  The
correct way to handle timeouts in systemd is to store them in the unit
file, which will ensure they are respected in any context that unit
may be called.

=item C<sleep>.

Used only in C<stop_sleep_start>. Determines the number of
seconds to sleep after C<stop> before proceeding with C<start>.

=item C<persistent>

Used only in the Solaris variant of C<start> and C<stop>.  Make the
enabling or disabling of this service persist in subsequent reboots.
Implies not passing the C<-t> flag to C<svcadm>.

=item C<recursive>.

Used only in the Solaris variant of C<start> and C<stop>.  Starts or
stops all the dependencies for the given daemons, too.

=item C<synchronous>

Used only in the Solaris variant of C<restart>.  Waits until all
services have been restarted.

If no C<timeout> was passed, it will wait forever.

=back

...

=back


=cut

sub _initialize
{
    my ($self, $services, %opts) = @_;

    %opts = () if !%opts;

    $opts{sleep} = $DEFAULT_SLEEP if(!exists($opts{sleep}));

    $self->{log} = delete $opts{log};

    $self->{services} = $services;
    $self->{options} = \%opts;
    return SUCCESS;
}

# Execute and log the result. Logs with error on failure,
# verbose on success. Returns 0 on error, 1 on success.
sub _logcmd
{
    my ($self, @cmd) = @_;

    my $proc = $self->create_process(@cmd);
    $proc->execute();
    my $method = $? ? "error" : "verbose";

    $self->$method("Command ", join(" ", @cmd), " produced stdout: ",
                     ${$proc->{OPTIONS}->{stdout}}, " and stderr: ",
                     ${$proc->{OPTIONS}->{stderr}});
    return !$?;
}

# Methods creating the appropriate CAF::Process for each platform.

# On SysV-based systems we have to kill the service command if things
# go out of control.
sub create_process_linux_sysv
{
    my ($self, @cmd) = @_;

    my $timeout = $self->{options}->{timeout};
    if(!defined($timeout)) {
        $self->debug(3, "Timeout undefined, set timeout to 0");
        $timeout=0;
    }

    my $proc = CAF::Process->new(\@cmd,
                                 log => $self->{log},
                                 timeout => $timeout,
                                 stdout => \my $stdout,
                                 stderr => \my $stderr);
    return $proc;
}

# On Systemd-based systems, timeouts must be ignored.
sub create_process_linux_systemd
{
    my ($self, @cmd) = @_;

    my $proc = CAF::Process->new(\@cmd,
                                 log => $self->{log},
                                 stdout => \my $stdout,
                                 stderr => \my $stderr);
    return $proc;
}

# On Solaris, timeouts specify how long we'll wait for the operation
# to complete, as described in the man page of svcadm.
sub create_process_solaris
{
    my ($self, @cmd) = @_;

    my $proc = CAF::Process->new(\@cmd,
                                 log => $self->{log},
                                 stdout => \my $stdout,
                                 stderr => \my $stderr);
    return $proc;
}

=pod

=head2 Public methods

=over

=item C<restart>

Restarts the daemons.

=item C<start>

Starts the daemons.

=item C<stop>

Stops the daemons

=item C<reload>

Reloads the daemons

=cut

# The start, stop, restart and reload methods are identical on each Linux
# variant.  We can generate them all in one go.
foreach my $method (@GENERATED_ACTIONS) {
    foreach my $flavour (@FLAVOURS) {
        # for flavour solaris, reload and restart are coded below
        next if ($flavour eq 'solaris' && ($method eq 'restart'  || $method eq 'reload'));

        no strict 'refs';
        *{"${method}_${flavour}"} = __make_method($method, $flavour);
        use strict 'refs';
    }
}

sub restart_solaris
{
    my $self = shift;

    my @cmd = ('svcadm', '-v', 'restart');

    # TODO timeout=0? -> defined() or not?
    push(@cmd, "-s") if $self->{options}->{synchronous} || $self->{options}->{timeout};
    push(@cmd, "-T", $self->{options}->{timeout}) if defined($self->{options}->{timeout});
    return $self->_logcmd(@cmd, @{$self->{services}});
}

sub reload_solaris
{
    my $self = shift;

    return $self->_logcmd(qw(svcadm -v refresh), @{$self->{services}});
}

=pod

=item C<stop_sleep_start>

Stops the daemon, sleep, and then start the dameon again.
Only when both C<stop> and C<start> are successful, return success.

=cut

# The C<stop_sleep_start> method reuses the C<stop> and C<start> methods.
# It accepts an argument that is the time to sleep, and precedes the
# sleep defined during initialization or the module default.
# Returns 1 if C<stop> and C<start> were successful, 0 otherwise.
sub stop_sleep_start
{
    my ($self, $sleep) = @_;

    $sleep = $self->{options}->{sleep} if (!defined($sleep));

	my $stop = $self->stop();
	sleep($sleep);
	my $start = $self->start();

	return $stop && $start;
}


=pod

=item os_flavour

Determine and return the OS flavour (/variant)

Current flavours are

=over

=item linux_sysv

Linux OS with SysV int system

=item linux_systemd

Linux OS with systemd

=item solaris

Solaris OS

=back

(All supported flavours are exported via C<@FLAVOURS>.)

=cut

# Determine the OS flavour. (Also allows mocking the flavour for unittests)
sub os_flavour
{
    my $flavour;
    if ($^O eq 'linux') {
        $flavour = "linux";
        if (-x "/bin/systemctl") {
            $flavour .= "_systemd";
        } elsif (-x "/sbin/service") {
             $flavour .= "_sysv";
        } else {
            die "Unsupported Linux version. Unable to run $AUTOLOAD";
        }
    } elsif ($^O eq 'solaris') {
        $flavour = "solaris";
    } else {
        die "Unsupported operating system: $^O. Not running $AUTOLOAD";
    }

    if (! defined($flavour)) {
        die "Undefined flavour for operating system: $^O. Not running $AUTOLOAD";
    }

    if(grep {$_ eq $flavour} @FLAVOURS) {
        return $flavour;
    } else {
        die "Determined flavour $flavour, but not part of exported FLAVOURS. (Please report this bug.)";
    }
}

=pod

=back

=head2 Private methods

=over

=item __make_method

A generator for service methods, to be used in e.g.
subclassing. In the example below we create a custom service
class that supports e.g. 'service myservice init':

    package MyService;

    use CAF::Service qw(__make_method @FLAVOURS);
    use parent qw(CAF::Service);

    sub _initialize {
        my ($self, %opts) = @_;
        return $self->SUPER::_initialize(['myservice'], %opts);
    }

    my $method = 'init';
    foreach my $flavour (@FLAVOURS) {
        no strict 'refs';
        *{"${method}_${flavour}"} = __make_method($method, $flavour);
        use strict 'refs';
    }

    1;

This class can than be used in the same way as C<CAF::Service>

    use MyService;
    ...
    my $serv = MyService->new();
    $serv->init();
    ...
    $serv->reload();

=cut

sub __make_method
{
    my ($method, $flavour) = @_;

    if ($flavour eq 'linux_sysv') {
        return sub {
            my $self = shift;
            my $ok = 1;

            foreach my $i (@{$self->{services}}) {
                $ok &&= $self->_logcmd("service", $i, $method);
            }
            return $ok;
        };
    } elsif ($flavour eq 'linux_systemd') {
        return sub {
            my $self = shift;
            return $self->_logcmd("systemctl", $method,
                                  map { m/\.(service|target)$/ ? $_ : "$_.service" } @{$self->{services}} );
        };
    } elsif ($flavour eq 'solaris') {
        return sub {
            my $self = shift;

            my @cmd = ('svcadm', '-v', $SOLARIS_METHODS{$method});

            push(@cmd, "-r") if $self->{options}->{recursive};
            push(@cmd, "-t") if !$self->{options}->{persistent};

            return $self->_logcmd(@cmd, @{$self->{services}});
        };
    } else {
        # TODO: Return an undef or empty anonymous sub?
        return;
    }
}

# Choose the correct variant for each daemon action.  All the
# OS-dependent logic is here.  See perldoc perlsub for details on how
# AUTOLOAD works.
sub AUTOLOAD
{
    my ($self, @args) = @_;

    my $called = $AUTOLOAD;

    # Don't mess with garbage collection!
    return if $called =~ m{DESTROY};

    my $called_orig = $called;
    $called =~ s{.*::}{};
    my $called_orig_short = $called;
    $called .= "_" . os_flavour();

    if ($self->can($called)) {
        # Run the expected method.
        # AUTOLOAD with glob assignment and goto defines the autoloaded method
        # (so they are only autoloaded once when they are first called),
        # but that breaks inheritance.
        $self->$called(@args);
    } else {
        die "Unknown method: $called (from original $called_orig / short $called_orig_short)";
    }
}


1;

__END__

=pod

=back

=cut
