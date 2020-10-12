use strict;
use warnings;
use Test::More;
use Test::Quattor;
use CAF::Service qw(@ALL_ACTIONS);
use CAF::ServiceActions qw(@SERVICE_ACTIONS);
use Test::MockModule;
use Test::Quattor::Object;

my $obj = Test::Quattor::Object->new();

set_service_variant("linux_systemd");

is_deeply(\@SERVICE_ACTIONS, [qw(restart reload stop_sleep_start condrestart)], "expected service actions");

foreach my $act (@SERVICE_ACTIONS) {
    ok((grep {$_ eq $act} @ALL_ACTIONS), "serviceaction $act is a CAF::Service action");
}

command_history_reset;
my $sa = CAF::ServiceActions->new(log => $obj);
isa_ok($sa, 'CAF::ServiceActions', 'new returns a CAF::ServiceActions instance');

$sa->add({daemon1 => 'restart', daemon2 => 'reload'});
$sa->add({daemon4 => 'condrestart'});
$sa->add({daemon3 => 'restart'}, msg => 'test long');
is($obj->{LOGLATEST}->{VERBOSE}, 'Scheduled daemon/action daemon3:restart test long',
   'expected reported verbose message including msg long');

my $sched = {
    reload => {daemon2 => 1},
    restart => {daemon1 => 1, daemon3 => 1},
    condrestart => {daemon4 => 1},
};
is_deeply($sa->{actions}, $sched, "expected added actions long");

$sa->add(undef, msg => 'test undef');
is_deeply($sa->{actions}, $sched, "expected added actions long after undef");
is($obj->{LOGLATEST}->{VERBOSE}, 'No daemon/action scheduled test undef',
   'expected reported verbose message including msg undef');


ok(!@Test::Quattor::command_history, "No commands run before run");
$sa->run();
ok(command_history_ok(["systemctl condrestart daemon4.service",
                       "systemctl reload daemon2.service",
                       "systemctl restart daemon1.service",
                       "systemctl restart daemon3.service"]),
   "run runs expected commands long");
ok(!$obj->{LOGLATEST}->{ERROR}, "no errors long");

command_history_reset;
my $sa2 = CAF::ServiceActions->new(log => $obj, pairs => {daemon1 => 'restart', daemon2 => 'reload'}, msg => 'test short');
is_deeply($sa2->{actions}, {
    reload => {daemon2 => 1},
    restart => {daemon1 => 1},
    }, "expected added actions short");
is($obj->{LOGLATEST}->{VERBOSE}, 'Scheduled daemon/action daemon1:restart, daemon2:reload test short',
   'expected reported verbose message including msg short');
$sa2->run();
ok(!$obj->{LOGLATEST}->{ERROR}, "no errors short");
ok(command_history_ok(["systemctl reload daemon2.service", "systemctl restart daemon1.service"]),
   "run runs expected commands short");


command_history_reset;
my $sa3 = CAF::ServiceActions->new(log => $obj);
$sa3->add({daemon1 => 'stop', daemon2 => 'reload'}, msg => 'test wrong');
is($obj->{LOGLATEST}->{VERBOSE}, 'Scheduled daemon/action daemon2:reload test wrong',
   'expected reported verbose message including msg wrong');
like($obj->{LOGLATEST}->{ERROR}, qr{^Not a CAF::ServiceActions allowed action stop for daemon daemon1 .*? test wrong$},
   'expected reported error message including msg wrong');
is_deeply($sa3->{actions}, {reload => {daemon2 => 1}}, "invalid action skipped");
$sa3->run();
ok(command_history_ok(["systemctl reload daemon2.service"], ['daemon1']),
   "run runs expected commands wrong (no daemon1)");


done_testing;
