# -*- perl -*-
use strict;
use warnings;
use Test::More;
use Test::Quattor;
use CAF::Service;

=pod

=head1 SYNOPSIS

Test all methods for C<CAF::Service>

=cut

# We forcefully choose one of the create_process implementations,
# since we are not interested in the behaviour of AUTOLOAD at this
# stage.
*CAF::Service::create_process = \&CAF::Service::create_process_linux_systemd;

my $srv = CAF::Service->new(['ntpd', 'sshd']);


foreach my $m (qw(start stop restart)) {
    my $method = "${m}_linux_systemd";
    $srv->$method();
    ok(get_command("systemctl $m ntpd sshd"), "systemctl $m works");
}


*CAF::Service::create_process = \&CAF::Service::create_process_linux_sysv;
foreach my $m (qw(start stop restart)) {
    my $method = "${m}_linux_sysv";
    $srv->$method();
    ok(get_command("service ntpd $m"), "sysv $m works");
    ok(get_command("service sshd $m"),
       "sysv $m works on all elements of the services list");
}

*CAF::Service::create_process = \&CAF::Service::create_process_solaris;

foreach my $m (qw(start stop restart)) {
    my $method = "${m}_solaris";
    $srv->$method();
    ok(get_command("svcadm $m ntpd sshd"), "svcadm $m works");
}

$srv->{timeout} = 42;
$srv->restart_solaris();

ok(get_command("svcadm restart -s -T $srv->{timeout} ntpd sshd"),
   "svcadm restart handles timeouts the Solaris way");

done_testing();
