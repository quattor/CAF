# -*- perl -*-
use strict;
use warnings;
use Test::More;
use Test::Quattor;
use CAF::Service;
use Test::MockModule;

=pod

=head1 SYNOPSIS

Test all methods for C<CAF::Service>

=cut

my $srv = CAF::Service->new(['ntpd', 'sshd']);


=pod

=head2 Test systemd

Test all methods for C<CAF::Service> for linux_systemd

=cut

set_service_variant("linux_systemd");


foreach my $m (qw(start stop restart reload)) {
    my $method = "${m}_linux_systemd";
    $srv->$method();
    ok(get_command("systemctl $m ntpd.service sshd.service"), "systemctl $m works");
}
command_history_reset;
$srv->stop_sleep_start(1);
ok(command_history_ok(["systemctl stop ntpd.service sshd.service",
                       "systemctl start ntpd.service sshd.service"
                       ]), "stop_sleep_start systemctl works");


=pod

=head2 Test sysv

Test all methods for C<CAF::Service> for linux_sysv

=cut


set_service_variant("linux_sysv");

foreach my $m (qw(start stop restart reload)) {
    my $method = "${m}_linux_sysv";
    $srv->$method();
    ok(get_command("service ntpd $m"), "sysv $m works");
    ok(get_command("service sshd $m"),
       "sysv $m works on all elements of the services list");
}
command_history_reset;
$srv->stop_sleep_start(1);
ok(command_history_ok(["service ntpd stop",
                       "service sshd stop", 
                       "service ntpd start",
                       "service sshd start"
                       ]), "stop_sleep_start sysv works");

=pod

=head2 Test solaris

Test all methods for C<CAF::Service> for solaris

=cut

set_service_variant("solaris");

$srv->restart_solaris();
ok(get_command("svcadm -v restart ntpd sshd"), "svcadm restart works");
$srv->start_solaris();
ok(get_command("svcadm -v enable -t ntpd sshd"), "svcadm enable/start works");
$srv->stop_solaris();
ok(get_command("svcadm -v disable -t ntpd sshd"), "svcadm disable/stop works");

$srv->reload_solaris();
ok(get_command('svcadm -v refresh ntpd sshd'),
   "reload mapped to svcadm's refresh operation");

$srv->{timeout} = 42;
$srv->restart_solaris();

ok(get_command("svcadm -v restart -s -T $srv->{timeout} ntpd sshd"),
   "svcadm restart handles timeouts the Solaris way");

command_history_reset;
$srv->stop_sleep_start(1);
ok(command_history_ok(["svcadm -v disable -t ntpd sshd",
                       "svcadm -v enable -t ntpd sshd" 
                      ]), "stop_sleep_start svcadm disable/stop works");

done_testing();
