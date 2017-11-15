use strict;
use warnings;

# hello mocking
my $iddata;
my $idcalled;
BEGIN {
    # Before CAF::Process
    *CORE::GLOBAL::getpwuid = sub {$idcalled->{getpwuid} += 1;return @{$iddata->{getpwuid}};};
    *CORE::GLOBAL::getpwnam = sub {$idcalled->{getpwnam} += 1;return @{$iddata->{getpwnam}};};
    *CORE::GLOBAL::getgrnam = sub {$idcalled->{getgrnam} += 1;return @{$iddata->{getgrnam}};};
    *CORE::GLOBAL::getgrgid = sub {$idcalled->{getgrgid} += 1;return @{$iddata->{getgrgid}};};
}


use FindBin qw($Bin);
use lib "$Bin/modules";
use testapp;
use CAF::Process;
use Test::More;
use Test::Quattor::Object;

use Test::MockModule;
my $mock = Test::MockModule->new ("CAF::Process");

# After CAF::Process
no warnings 'redefine';
*CAF::Process::_uid = sub {$idcalled->{uid} += 1;return $iddata->{uid};};
*CAF::Process::_euid = sub {$idcalled->{euid} += 1;return $iddata->{euid};};
*CAF::Process::_gid = sub {$idcalled->{gid} += 1;return $iddata->{gid};};
*CAF::Process::_egid = sub {$idcalled->{egid} += 1;return $iddata->{egid};};
*CAF::Process::_set_euid = sub {$idcalled->{seuid} += 1;$iddata->{euid} = $_[0];};
*CAF::Process::_set_egid = sub {$idcalled->{segid} += 1;$iddata->{egid} = $_[0];};
use warnings 'redefine';

$iddata = {
    uid => 122,
    euid => 122,
    gid => "123 123 10 20 30",
    egid => "123 123 10 20 30",
    getpwuid => [qw(myself x 122 123)],
    getpwnam => [qw(myself x 122 123)],
    getgrgid => [qw(mygroup alias 123 myself)],
    getgrnam => [qw(mygroup alias 123 myself)],
};

my $obj = Test::Quattor::Object->new();

my ($p, $this_app, $str, $fh, $out, $out2);

our ($run, $trun, $execute, $output, $toutput) = (0, 0, 0, 0, 0);
our %opts = ();
our $cmd = [];

sub init_test
{
    $cmd = [];
    %opts = ();
}

# is_executable tests
# no test non-existing filename (the mock function would just return the path)
sub test_executable {
    my ($self, $executable) = @_;
    return $executable;
}
$mock->mock ("_test_executable", \&test_executable);

# the executable should be resolvable via which (lets assume ls is in PATH)
my $command = [qw (ls a random command which I do not care)];

open ($fh, ">", \$str);
$this_app = testapp->new ($0, qw (--verbose));
$this_app->config_reporter(logfile => $fh);

=head2 Test no logging

=cut

$p = CAF::Process->new ($command);
$p->execute ();
is ($execute, 1, "execute called with no logging");
ok (@$cmd == @$command, "Correct command called by execute");
ok (!defined ($str), "Nothing logged by execute");
init_test();
$p->run ();
is ($run, 1, "run called with no logging");
ok (@$cmd == @$command, "Correct command called by run");
ok (!defined ($str), "Nothing logged by run");
init_test();
$p->output();
is ($output, 1, "output called with no logging");
ok (@$cmd == @$command, "Correct command called by output");
ok (!defined ($str), "Nothing logged by output");
init_test();$p->trun (10);
is ($trun, 1, "trun called with no logging");
ok (@$cmd == @$command, "Correct command called by trun");
ok (!defined ($str), "Nothing logged by trun");
init_test();
$p->toutput(10);
is ($toutput, 1, "toutput called with no logging");
ok (@$cmd == @$command, "Correct command called by toutput");
ok (!defined ($str), "Nothing logged by toutput");
init_test();


=head2 Test with logging

=cut

# Let's test this with a few options, especially logging.
$p = CAF::Process->new ($command, log => $this_app,
			stdin => "Something");
$p->execute ();
is ($execute, 2, "execute with options correctly run");
like ($str, qr/Executing.*ls a random command.*stdin.*Something/,
      "execute used the correct options and was correctly logged");
is ($opts{stdin}, "Something", "Execute applied the correct options");

$str = "";
open ($fh, ">", \$str);
$this_app->config_reporter(logfile => $fh);
$p = CAF::Process->new ($command, log => $this_app,
                        stdin => "Something");
ok($p->is_executable(), "Command is executable");
my $res = $p->execute_if_exists ();
is ($execute, 3, "execute_if_exists runs execute");
like ($str, qr/Executing.*ls a random command.*stdin.*Something/,
      "execute_if_exists does the same as execute");
is ($opts{stdin}, "Something", "execute_if_exists does the same thing as execute");


$str = "";
open ($fh, ">", \$str);
$this_app->config_reporter(logfile => $fh);
$p->run ();
is ($run, 2, "Logged run correctly run");
like ($str, qr/Running the command: ls a random command/,
      "run logged");
$p->output ();
is ($output, 2, "output with options correctly run");
like ($str, qr/Getting output of command: ls a random command/,
      "output used the correct options and was correctly logged");
$str = "";
open ($fh, ">", \$str);
$this_app->config_reporter(logfile => $fh);
$p->trun (10);
is ($trun, 2, "Logged trun correctly run");
like ($str, qr/Running the command: ls a random command.* with 10 seconds/,
      "trun logged");
$str = "";
open ($fh, ">", \$str);
$this_app->config_reporter(logfile => $fh);
$p->toutput (10);
is ($toutput, 2, "Logged toutput correctly run");
like ($str, qr/Getting output of command: ls a random command.* with 10 seconds/,
      "toutput logged");

$str = "";
open ($fh, ">", \$str);
$this_app->config_reporter(logfile => $fh);
my $ps = CAF::Process->new ($command, log => $this_app,
			stdin => "Something", sensitive => 1);
$ps->run ();
like ($str, qr/Running the command: ls <sensitive>/,
      "run logged with sensitive mode (command not in log)");

# _sensitive_commandline
$ps->{sensitive} = undef;
is($ps->_sensitive_commandline(), join(" ", @$command),
   "expected commandline w/o sensitive");

$ps->{sensitive} = 1;
is($ps->_sensitive_commandline(), 'ls <sensitive>',
   "expected commandline w sensitive=1");

# one key is a substring of another,
# control the order by the value
# tip: use long random passwords ;)
$ps->{sensitive} = {
    a => 'LETTERA',
    random => 'ASECRET',
    '.*' => 'A', # should not match, even if it runs first
};
is($ps->_sensitive_commandline(),
   'ls LETTERA ASECRET commLETTERAnd which I do not cLETTERAre',
   "expected commandline w sensitive=hashref");


my $sens_function = sub {
    return join(",", @{$_[0]}[0..2]);
};
$ps->{sensitive} = $sens_function;
is($ps->_sensitive_commandline(), 'ls,a,random',
   "expected commandline w sensitive=funcref");

my $sens_function_die = sub {
    die("magic");
};
$ps->{sensitive} = $sens_function_die;
is($ps->_sensitive_commandline(),
   'ls <sensitive> (sensitive function failed, contact developers)',
   "expected commandline w sensitive=funcref and failure");

=head2 pushargs / setopts

=cut

init_test();
# Let's test the rest of the commands
$p->pushargs (qw (this does not matter at all));
push (@$command, qw (this does not matter at all));
$p->setopts (stdout => \$str);
$p->execute ();
is ($opts{stdin}, "Something", "Option from creation is respected");
is (${$opts{stdout}}, $str, "Correct stdout");
ok (@$cmd == @$command, "The command got options appended");
$str = undef;
$p->setopts (stdout => \$str);
is($str, "", "Stdout is initialized");

=head2  Test the NoAction flag

=cut

$CAF::Object::NoAction = 1;
init_test();
$p = CAF::Process->new($command);
ok (!@$cmd, "LC::Process::execute not called with NoAction");
is ($p->output(), "", "The ouptut with NoAction is empty");
ok (!@$cmd, "LC::Process::output not called with NoAction");
is ($p->run(), 0, "Run returns the expected value with NoAction");
ok (!@$cmd, "LC::Process::run not called with NoAction");
is ($p->toutput(10), "", "The toutput with NoAction is empty");
ok (!@$cmd, "LC::Process::toutput not called with NoAction");
is ($p->trun(10), 0,
    "LC::Process::trun returns the expected value with NoAction");
ok (!@$cmd, "LC::Process::trun not called with NoAction");
ok($p->{NoAction}, "By default assume the command changes the system state");
$p = CAF::Process->new($command, keeps_state => 1);
ok(!$p->{NoAction},
   "NoAction invalidated because command doesn't change the state");

$p = CAF::Process->new($command, keeps_state => 0);
ok($p->{NoAction}, "Respect NoAction if the command changes the state");

=head2 stringification

=cut

$p = CAF::Process->new($command);
my $command_str = join(" ", @$command);
is($p->stringify_command, $command_str, "stringify_command returns joined command");
is("$p", $command_str, "overloaded stringification");

=head2 is_executable / get_executable

=cut

is(join(" ", @{$p->get_command}), $command_str, "get_command returns ref to command list");
is($p->get_executable, "ls", "get_executable returns executable");

$p = CAF::Process->new([qw(ls)]); # let's assume that ls exists
is($p->get_executable, "ls", "get_executable returns executable");
my $ls = $p->is_executable;
like($ls, qr{^/.*ls$}, "Test ls basename resolved to absolute path");

$p = CAF::Process->new([$ls]);
is($p->is_executable, $ls, "Test absolute path");

$p = CAF::Process->new([qw(doesnotexists)]);
ok(! defined($p->is_executable), "Test can't resolve basename");
is($p->execute_if_exists, 1, "Fails to execute non-existing executable, returns 1");

# empty command process
$p = CAF::Process->new([]);
is("$p", "", "Empty command process is empty string");
ok(! $p, "Empty process is logical false (autogeneration of overloaded bool via new stringify)");

=head2 _set_eff_user_group / _set_uid_gid / _get_uid_gid

=cut

$p = CAF::Process->new ($command, log => $obj);
$p->{user} = undef;
$p->{group} = undef;
is_deeply([$p->_get_uid_gid('user')], [], "_get_uid_gid user returns empty array on missing user attr");
is_deeply([$p->_get_uid_gid('group')], [], "_get_uid_gid group returns empty array on missing group attr");

$idcalled = {};
$p->{user} = 'x';
is_deeply([$p->_get_uid_gid('user')], [122, 123], "get_uid_gid user returns uid and prim gid");
is_deeply($idcalled, {getpwnam => 1}, 'get_uid_gid user used pwnam');

$idcalled = {};
$p->{user} = 122;
is_deeply([$p->_get_uid_gid('user')], [122, 123], "get_uid_gid user id returns uid and prim gid");
is_deeply($idcalled, {getpwuid => 1}, 'get_uid_gid user id used pwuid');

$idcalled = {};
$p->{group} = 'x';
is_deeply([$p->_get_uid_gid('group')], [123, undef], "get_uid_gid group returns gid and undef");
is_deeply($idcalled, {getgrnam => 1}, 'get_uid_gid group used grnam');

$idcalled = {};
$p->{group} = 123;
is_deeply([$p->_get_uid_gid('group')], [123, undef], "get_uid_gid group id returns gid and undef");
is_deeply($idcalled, {getgrgid => 1}, 'get_uid_gid group id used grgid');

# unknown userid
$idcalled = {};
$iddata->{getpwuid} = []; # empty list means unknown user
$p->{user} = 122;
is_deeply([$p->_get_uid_gid('user')], [], "get_uid_gid user id returns empty array with unknown userid");
is_deeply($idcalled, {getpwuid => 1}, 'get_uid_gid user id used pwuid with unknown userid');
is($obj->{LOGLATEST}->{ERROR}, 'No such user 122 (is user 1; is id 1)',
   'error reported with with unknown userid');


$idcalled = {};
$p->{user} = 'x';
$iddata->{getpwuid} = [qw(myself x 122 123)];
$p->{group} = undef;

my $value = [];
my $valueidx = 0;
my $setargs = [];

my $get = sub {
    $valueidx += 1;
    # If there's an error, the message will be "No such file or directory"
    $! = 2;
    return $value->[$valueidx-1];
};
my $set = sub {push(@$setargs, \@_); return $!};

$valueidx = 0;
$setargs = [];
$value = [123];
ok($p->_set_uid_gid(123, $set, $get, "something", "suffix", "update"),
   "set_uid_gid returns ok if target is current value");
is_deeply($setargs, [], "set not called, target is current value");

$valueidx = 0;
$setargs = [];
$value = [122, 123];
ok($p->_set_uid_gid(123, $set, $get, "something", "suffix", "update"),
   "set_uid_gid returns ok when target set");
is_deeply($setargs, [[123]], "set called with target success");

$valueidx = 0;
$setargs = [];
$value = [122, 122];
ok(!$p->_set_uid_gid(123, $set, $get, "something", "suffix", "update"),
   "set_uid_gid fails when set failed");
is_deeply($setargs, [[123]], "set called with target failure");
is($obj->{LOGLATEST}->{ERROR},
   "Something went wrong update something from '122' to suffix: new something '122', reason No such file or directory",
   "error reported when failed to set target");

$valueidx = 0;
$setargs = [];
$value = [1, 1]; # success
$mock->mock('_set_uid_gid', sub {
    # can't compare the methods for some reason
    push(@$setargs, [$_[1], $_[4], $_[5], $_[6]]);
    $valueidx += 1;
    return $value->[$valueidx-1];
});

$valueidx = 0;
$setargs = [];
$value = [1, 1]; # success
ok($p->_set_eff_user_group(), "_set_eff_user_group ok");
is_deeply($setargs, [
    ['123 123', 'EGID', "'123 123' with GID '123 123 10 20 30'", 'changing'],
    ['122', 'EUID', '122 with UID 122', 'changing'],
], "_set_uid_gid called as expected (EGID before EUID)");

$valueidx = 0;
$setargs = [];
$value = [0, 1]; # one failure
ok(! $p->_set_eff_user_group(), "_set_eff_user_group failed 1st");

is_deeply($setargs, [
    ['123 123', 'EGID', "'123 123' with GID '123 123 10 20 30'", 'changing'],
], "_set_uid_gid failed, only first called");

$valueidx = 0;
$setargs = [];
$value = [1, 0]; # one failure
ok(! $p->_set_eff_user_group(), "_set_eff_user_group failed 2nd");
is_deeply($setargs, [
    ['123 123', 'EGID', "'123 123' with GID '123 123 10 20 30'", 'changing'],
    ['122', 'EUID', '122 with UID 122', 'changing'],
], "_set_uid_gid failed, first and second called");

# restore original
$valueidx = 0;
$setargs = [];
$value = [1, 1]; # success
my $orig = [124, "124 124 80 90"];
ok($p->_set_eff_user_group($orig), "_set_eff_user_group ok restore");
diag explain $setargs;
is_deeply($setargs, [
    ['124', 'EUID', '124 with UID 122', 'restoring'],
    ['124 124 80 90', 'EGID', "'124 124 80 90' with GID '123 123 10 20 30'", 'restoring'],
], "_set_uid_gid called as expected (EUID before EGID) restore");

$valueidx = 0;
$setargs = [];
$value = [0, 1]; # one failure
ok(! $p->_set_eff_user_group($orig), "_set_eff_user_group failed 1st restor");

is_deeply($setargs, [
    ['124', 'EUID', '124 with UID 122', 'restoring'],
], "_set_uid_gid failed, only first called restore");

$valueidx = 0;
$setargs = [];
$value = [1, 0]; # one failure
ok(! $p->_set_eff_user_group($orig), "_set_eff_user_group failed 2nd restore");
is_deeply($setargs, [
    ['124', 'EUID', '124 with UID 122', 'restoring'],
    ['124 124 80 90', 'EGID', "'124 124 80 90' with GID '123 123 10 20 30'", 'restoring'],
], "_set_uid_gid failed, first and second called restore");

=head2 run as user

=cut

# insert the mocking here
my $args;
$mock->mock('_set_eff_user_group', sub {shift; push(@$args, \@_); return 1});
$CAF::Object::NoAction = 1;
$execute = 0;
$idcalled = {};
$p = CAF::Process->new ($command, log => $obj);
$p->execute ();
is ($execute, 0, "execute called with for user test w NoAction=1");
is_deeply($idcalled, {}, "none of the user methods called w NoAction=1");
ok(!defined $args, "_set_eff_user_group not called w NoAction=1");

$CAF::Object::NoAction = 0;
$execute = 0;
$idcalled = {};
$p = CAF::Process->new ($command, log => $obj);
$p->execute ();
is ($execute, 1, "execute called with for user test w/o user");
is_deeply($idcalled, {}, "none of the user methods called w/o user");
ok(!defined $args, "_set_eff_user_group not called w/o user");

$CAF::Object::NoAction = 1;
$execute = 0;
$idcalled = {};
$p = CAF::Process->new ($command, log => $obj, user => 'x');
$p->execute ();
is ($execute, 0, "execute called with for user test w NoAction=1 with user");
is_deeply($idcalled, {}, "none of the user methods called w NoAction=1 with user");
ok(!defined $args, "_set_eff_user_group not called wNoAction=1 with user");
$p = CAF::Process->new ($command, log => $obj, group => 'x');
$p->execute ();
is ($execute, 0, "execute called with for user test w NoAction=1 with group");
is_deeply($idcalled, {}, "none of the user methods called w NoAction=1 with group");
ok(!defined $args, "_set_eff_user_group not called wNoAction=1 with group");

$CAF::Object::NoAction = 0;
$execute = 0;
$idcalled = {};
$p = CAF::Process->new ($command, log => $obj, user => 'x');
$p->execute ();
is ($execute, 1, "execute called with for user test w user");
is_deeply($idcalled, {uid => 1, gid => 1},
          "uid/gid called (to determine orig user/group) w user");
is_deeply($args, [[], [[122, "123 123 10 20 30"]]],
          "_set_eff_user_group called w/o args first and then with original uid/gid args w user");

$args = undef;
$execute = 0;
$idcalled = {};
$p = CAF::Process->new ($command, log => $obj, group => 'x');
$p->execute ();
is ($execute, 1, "execute called with for user test w group");
is_deeply($idcalled, {uid => 1, gid => 1},
          "uid/gid called (to determine orig user/group) w group");
is_deeply($args, [[], [[122, "123 123 10 20 30"]]],
          "_set_eff_user_group called w/o args first and then with original uid/gid args w group");

done_testing();
