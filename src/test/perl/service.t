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

my $mock = Test::MockModule->new("CAF::Service");
$mock->mock("os_flavour", "linux_systemd");


my $srv = CAF::Service->new(['ntpd', 'sshd']);


foreach my $m (qw(start stop restart reload)) {
    my $method = "${m}_linux_systemd";
    $srv->$method();
    ok(get_command("systemctl $m ntpd.service sshd.service"), "systemctl $m works");
}


*CAF::Service::create_process = \&CAF::Service::create_process_linux_sysv;
foreach my $m (qw(start stop restart reload)) {
    my $method = "${m}_linux_sysv";
    $srv->$method();
    ok(get_command("service ntpd $m"), "sysv $m works");
    ok(get_command("service sshd $m"),
       "sysv $m works on all elements of the services list");
}

*CAF::Service::create_process = \&CAF::Service::create_process_solaris;

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

done_testing();
