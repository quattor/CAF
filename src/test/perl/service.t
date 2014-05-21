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

# Forcefully choose one of the create_process implemantations. We pick
# solaris because it has a peculiar way to handle timeouts.
# TODO: Move the process handling to a lower area.
*CAF::Service::create_process = \&CAF::Service::create_process_linux_systemd;

my $srv = CAF::Service->new(['ntpd']);

$srv->restart_linux_systemd();
ok(get_command("systemctl restart ntpd"), "systemctl restart works");
*CAF::Service::create_process = \&CAF::Service::create_process_linux_sysv;
$srv->restart_linux_sysv();
ok(get_command("service ntpd restart"), "sysv restart works");
*CAF::Service::create_process = \&CAF::Service::create_process_solaris;
$srv->restart_solaris();
ok(get_command("svcadm restart ntpd"), "svcadm restart works");

$srv->{timeout} = 42;
$srv->restart_solaris();

ok(get_command("svcadm restart -s -T $srv->{timeout} ntpd"),
   "svcadm restart handles timeouts the Solaris way");


done_testing();
