# ${license-info}
# ${developer-info
# ${author-info}
# ${build-info}
#
#
# CAF::Service class

package CAF::Service;

use strict;
use warnings;
use CAF::Process;

our $AUTOLOAD;
use base qw(CAF::Object);

# Mapping the methods we expose here to the svcadm operations. We
# choose the Linux terms for our API.
use constant SOLARIS_METHODS => {
    start => 'enable',
    stop => 'disable',
    restart => 'restart'
};

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
    $srv->stop_sleep_start($delay);

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

=cut

sub _initialize
{
    my ($self, $services, %opts) = @_;

    %opts = () if !%opts;
    $self->{services} = $services;
    $self->{options} = \%opts;
    return $self;
}

sub _logcmd
{
    my ($self, @cmd) = @_;

    my $proc = $self->create_process(@cmd);
    $proc->execute();
    my $logger = $self->{options}->{log};
    my $method = $? ? "error" : "verbose";

    $logger->$method("Command ", join(" ", @_), " produced stdout: ",
                     "$proc->{OPTIONS}->{stdout} and stderr: ",
                     $proc->{OPTIONS}->{stderr})
        if $logger;
    return !$?;
}

# Methods creating the appropriate CAF::Process for each platform.

# On SysV-based systems we have to kill the service command if things
# go out of control.
sub create_process_linux_sysv
{
    my ($self, @cmd) = @_;

    my $proc = CAF::Process->new(\@cmd,
                                 log => $self->{options}->{log},
                                 timeout => $self->{options}->{timeout},
                                 stdout => \my $stdout,
                                 stderr => \my $stderr);
    return $proc;
}

# On Systemd-based systems, timeouts must be ignored.
sub create_process_linux_systemd
{
    my ($self, @cmd) = @_;

    my $proc = CAF::Process->new(\@cmd,
                                 log => $self->{options}->{log},
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
                                 log => $self->{options}->{log},
                                 stdout => \my $stdout,
                                 stderr => \my $stderr);
}



# The restart, start and stop methods are identical on each Linux
# variant.  We can generate them all in one go.
foreach my $method (qw(start stop restart)) {
    no strict 'refs';
    *{"${method}_linux_sysv"} = sub {
        my $self = shift;
        my $ok = 1;

        foreach my $i (@{$self->{services}}) {
            $ok &&= $self->_logcmd("service", $i, $method);
        }
        return $ok;
    };

    *{"${method}_linux_systemd"} = sub {
        my $self = shift;

        return $self->_logcmd("systemctl", $method, @{$self->{services}});
    };

    next if $method eq 'restart';

    *{"${method}_solaris"} = sub {
        my $self = shift;

        my @cmd = ('svcadm', '-v', SOLARIS_METHODS->{$method});

        push(@cmd, "-r") if $self->{recursive};
        push(@cmd, "-t") if !$self->{persistent};

        return $self->_logcmd(@cmd, @{$self->{services}});
    };
}

sub restart_solaris
{
    my $self = shift;

    my @cmd = ('svcadm', '-v', 'restart');

    push(@cmd, "-s") if $self->{synchronous} || $self->{timeout};
    push(@cmd, "-T", $self->{timeout}) if $self->{timeout};
    return $self->_logcmd(@cmd, @{$self->{services}});
}

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
    return $flavour
}

# Choose the correct variant for each daemon action.  All the
# OS-dependent logic is here.  See perldoc perlsub for details on how
# AUTOLOAD works.
sub AUTOLOAD
{
    my $self = shift;

    my $called = $AUTOLOAD;

    # Don't mess with garbage collection!
    return if $called =~ m{DESTROY};

    $called =~ s{.*::}{};
    $called .= "_" . os_flavour();

    if ($self->can($called)) {
        # Run the expected method. This is ugly but it's the way to do
        # AUTOLOAD.
        no strict 'refs';
        unshift(@_, $self);
        *$AUTOLOAD = \&$called;
        goto &$AUTOLOAD;
    } else {
        die "Unknown method: $called";
    }
}


1;

__END__

=head2 Public methods

=over

=item C<restart>

Restarts the daemons.

=item C<start>

Starts the daemons.

=item C<stop>

Stops the daemons

=back

=cut
