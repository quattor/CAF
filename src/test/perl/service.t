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

my $srv = CAF::Service->new(['ntpd']);

$srv->restart_linux_systemd();
ok(get_command("systemctl restart ntpd"), "systemctl restart works");
$srv->restart_linux_sysv();
ok(get_command("service ntpd restart"), "sysv restart works");
$srv->restart_solaris();
ok(get_command("svcadm restart ntpd"), "svcadm restart works");


done_testing();
