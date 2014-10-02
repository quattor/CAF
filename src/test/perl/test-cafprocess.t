#!/usr/bin/perl

use FindBin qw($Bin);
use lib "$Bin/";
use strict;
use warnings;
use testapp;
use CAF::Process;
use Test::More;

use Test::MockModule;
my $mock = Test::MockModule->new ("CAF::Process");

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
$this_app->set_report_logfile ($fh);

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
$this_app->set_report_logfile ($fh);
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
$this_app->set_report_logfile ($fh);
$p->run ();
is ($run, 2, "Logged run correctly run");
like ($str, qr/Running the command: ls a random command/,
      "run logged");
$p->output ();
is ($output, 2, "output with options correctly run");
like ($str, qr/Getting output of.*ls a random command/,
      "output used the correct options and was correctly logged");
$str = "";
open ($fh, ">", \$str);
$this_app->set_report_logfile ($fh);
$p->trun (10);
is ($trun, 2, "Logged trun correctly run");
like ($str, qr/Running command.*ls a random command.*with 10 seconds/,
      "trun logged");
$str = "";
open ($fh, ">", \$str);
$this_app->set_report_logfile ($fh);
$p->toutput (10);
is ($toutput, 2, "Logged toutput correctly run");
like ($str, qr/Returning the output.*ls a random command.*with 10 seconds/,
      "toutput logged");
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
# Test the NoAction flag
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

$p = CAF::Process->new($command);
my $command_str = join(" ", @$command);
is($p->stringify_command, $command_str, "stringify_command returns joined command");
is("$p", $command_str, "overloaded stringification");

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


done_testing();
