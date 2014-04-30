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

use base qw(CAF::Object CAF::Reporter);

=pod

=head1 NAME

CAF::Service - Class for starting and stopping daemons in different
platforms

=head1 SYNOPSIS

    use CAF::Service;
    my $srv = CAF::Service->new('ntpd', log => $self, %opts);
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

=item C<$daemon>

The daemon to be started.  It takes some extra optional arguments:

=item C<log>

A C<CAF::Reporter> object to log daemon activities to.

=item C<timeout>

Maximum execution time, in seconds, for the restart operations. If
it's too slow it will be killed.  If not defined, the command won't
time out.

=item C<instance>

Ignored on Linux.  In Solaris, this is the daemon instance to operate
on.

=back

...

=cut

sub _initialize
{
    my ($self, $daemon, %opts) = @_;

    $self->{daemon} = $daemon;
    $self->{options} = \%opts;
    return $self;
}

sub _logcmd
{
    my ($self, @cmd) = @_;

    my $proc = CAF::Process->new(\@cmd,
                                 log => $self->{options}->{log},
                                 timeout => $self->{options}->{timeout},
                                 stdout => \my $stdout,
                                 stderr => \my $stderr);
    $proc->execute();
    my $logger = $self->{options}->{log};
    my $method = $? ? "error" : "verbose";

    $logger->$method("Command ", join(" ", @_), " produced stdout: $stdout and stderr: $stderr")
        if $logger;
    return !$?;
}

# Note: we'll rely on Class::Std::AUTOMETHOD to select at runtime the
# correct implementation of each command.

=head2 Public methods

=over

=item restart

Restarts the daemon

=cut

sub restart_linux_sysv
{
    my $self = shift;

    return $self->_logcmd("service", $self->{daemon}, "restart");
}

sub restart_linux_systemd
{
    my $self = shift;

    return $self->_logcmd("systemctl", "restart", $self->{daemon});
}

# Stub method. To be improved by developers with experience in solaris
sub restart_sunos
{
    my ($self, @moreopts) = @_;

    my $daemon = $self->{daemon};

    if ($self->{options}->{instance}) {
        $daemon = "$self->{options}->{instance}:$daemon";
    }

    return $self->_logcmd("svcadm", "restart", $daemon);
}

1;
