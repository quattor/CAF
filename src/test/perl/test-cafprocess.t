#!/usr/bin/perl

use FindBin qw($Bin);
use lib "$Bin/", "$Bin/..", "$Bin/../../perl-LC";
use strict;
use warnings;
use testapp;
use CAF::Process;
use Test::More;

my ($p, $this_app, $str, $fh, $out, $out2);

our ($run, $trun, $execute, $output, $toutput) = (0, 0, 0, 0, 0);
our %opts = ();
our $cmd = [];

sub init_test
{
    $cmd = [];
    %opts = ();
}

my $command = [qw (a random command which I do not care)];

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
like ($str, qr/Executing.*a random command.*stdin.*Something/,
      "execute used the correct options and was correctly logged");
is ($opts{stdin}, "Something", "Execute applied the correct options");
$str = "";

open ($fh, ">", \$str);
$this_app->set_report_logfile ($fh);
$p->run ();
is ($run, 2, "Logged run correctly run");
like ($str, qr/Running the command: a random command/,
      "run logged");
$p->output ();
is ($output, 2, "output with options correctly run");
like ($str, qr/Getting output of.*a random command/,
      "output used the correct options and was correctly logged");
$str = "";
open ($fh, ">", \$str);
$this_app->set_report_logfile ($fh);
$p->trun (10);
is ($trun, 2, "Logged trun correctly run");
like ($str, qr/Running command.*a random command.*with 10 seconds/,
      "trun logged");
$str = "";
open ($fh, ">", \$str);
$this_app->set_report_logfile ($fh);
$p->toutput (10);
is ($toutput, 2, "Logged toutput correctly run");
like ($str, qr/Returning the output.*a random command.*with 10 seconds/,
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

done_testing();
