#!/usr/bin/perl

use strict;
use warnings;
use FindBin qw($Bin);
use lib "$Bin/modules";
use testapp;
use CAF::Reporter;
use CAF::Object;
use Test::More; # tests => 26;
use Test::MockModule;
use Scalar::Util qw(refaddr);

# El ingenioso hidalgo Don Quijote de La Mancha
use constant TEXT => <<EOF;
En un lugar de La Mancha, de cuyo nombre no quiero acordarme
no ha mucho tiempo que vivía un hidalgo de los de adarga antigua...
EOF

use constant FILENAME => "/my/test";

our %opts = ();
our $path;
our $file_changed = 1;
my ($log, $str);

our $report;
my $this_app = testapp->new ($0, qw (--verbose));

sub init_test
{
    $path = "";
    %opts = ();
    $report = 0;
}

our $cmd;
our $mock;
our $app;
our $execute_stdout = '';

BEGIN {
    $mock = Test::MockModule->new ("CAF::Process");
    $mock->mock ("execute", sub {
                     $cmd = $_[0];
                     ${$cmd->{OPTIONS}->{stdout}} .= $execute_stdout;
                     $? = 0;
                     return 1;
                 });

    $mock->mock ("run", sub {
                     $cmd = $_[0];
                     $? = 0;
                     return 1;
                });
    $app = Test::MockModule->new ('CAF::Application');
}

use CAF::FileWriter;

if ($^O eq 'linux') {
    isa_ok ($cmd, "CAF::Process", "restorecon hook enabled at load time");
}

open ($log, ">", \$str);
$this_app->set_report_logfile ($log);

init_test;
my $fh = CAF::FileWriter->new (FILENAME, mode => 0600);
print $fh TEXT;
ok (*$fh->{save}, "File marked to be saved");
$fh->close();
is ($opts{contents}, TEXT, "The file has the correct contents");
is ($opts{mode}, 0600, "The file is created with the correct permissions");
ok (!*$fh->{save},  "File marked not to be saved after closing");
is ($path, FILENAME, "The correct file is opened");
init_test;
$fh = CAF::FileWriter->new (FILENAME, mode => 0400);
print $fh TEXT;
$fh = "";
is ($opts{contents}, TEXT, "The file is written when the object is destroyed");
is ($opts{mode}, 0400, "The file gets the correct permissions when the object is destroyed");
is ($path, FILENAME, "Correct path opened on object destruction");

init_test;
$fh = CAF::FileWriter->new (FILENAME);
print $fh TEXT;
$fh->cancel;
is (*$fh->{save}, 0, "File marked not to be saved");
$fh->close;
is ($path, "", "No file is opened when cancelling");
ok (!exists ($opts{contents}), "Nothing is written after cancel");
init_test;
$fh = CAF::FileWriter->new (FILENAME, mode => 0600,
			    log => $this_app);
print $fh TEXT;
is ($str, "Opening file " . FILENAME,
    "Correct log message when creating the object");
$fh->close;
is ($opts{contents}, TEXT, "Correct contents written to the logged file");
is ($path, FILENAME, "Correct file opened with log");
my $re =  ".*File " . FILENAME . " was modified"; #
like($str, qr{$re},
     "Modified file correctly reported");
ok (!exists ($opts{LOG}), "No log information passed to LC::Check::file");
$fh = CAF::FileWriter->new (FILENAME, log => $this_app);
$fh->cancel();
like ($str, qr{Not saving file /}, "Cancel operation correctly logged");
$fh->close();
init_test;
$fh = CAF::FileWriter->open (FILENAME, log => $this_app,
			     backup => "foo",
			     mode => 0400,
			     owner => 100,
			     group => 200);
print $fh TEXT;
$fh->close();
is ($opts{backup}, "foo", "Checking options: correct backup option passed");
is ($opts{mode}, 0400, "Checking options: correct mode passed");
is ($opts{owner}, 100, "Checking options: correct owner passed");
is ($opts{group}, 200, "Checking options: correct group passed");
init_test;
$fh = CAF::FileWriter->new (FILENAME, log => $this_app);
$file_changed = 0;
$re = "File " . FILENAME . " was not modified";
$fh->close();
like($str, qr{$re},
     "Unmodified file correctly reported");

$CAF::Object::NoAction = 1;

init_test;
$fh = CAF::FileWriter->open (FILENAME, log => $this_app,
			     backup => "foo",
			     mode => 0400,
			     owner => 100,
			     group => 200);
print $fh TEXT;
is ("$fh", TEXT, "Stringify works");
like ($fh, qr(En un lugar), "Regexp also works");
$fh->close();
ok(exists ($opts{noaction}), "NoAction flag is passed to LC");

# Check that the diff works
close($log);
open ($log, ">", \$str);
*testapp::report = sub { $report = 1; };

$this_app->set_report_logfile ($log);
init_test();
$fh = CAF::FileWriter->open ($INC{"CAF/FileWriter.pm"}, log => $this_app);
print $fh "hello, world\n";
# Mock diff output via CAF::Process execute()
$execute_stdout = "+ something changed";

$fh->close();
like($str, qr{Changes to \S+:}, "Diff is reported");
ok(!$cmd->{NoAction},
   "Diff will be shown even with noaction");

# No diffs if no contents
close ($log);
open ($log, ">", \$str);
$fh->close();
unlike($str, qr{Changes to \S+:}, "Diff not reported on already closed file");

# No diffs printed if not verbose
$CAF::Reporter::_REP_SETUP->{VERBOSE} = 0;
init_test();
$fh = CAF::FileWriter->open ($INC{"CAF/FileWriter.pm"}, log => $this_app);
print $fh "hello world\n";
$fh->close();
is($report, 0, "Diff output is reported only with verbose");

# Reset mocked diff via execute_stdout
undef $cmd;
$execute_stdout = '';

# Test events via CAF::History
# and legacy add_files
$app->mock('add_files', sub {
           my ($self, @args) = @_;
           $self->{FILES} = \@args;
       });
# no need to track time
$app->mock('_now', 0);

# no history until now, thisapp doesn't init_history on new()
ok(! defined($this_app->{HISTORY}), 'No history tracked this far');

$this_app->init_history(); # no instance tracking
ok(defined($this_app->{HISTORY}), 'history tracked enabled');

# there's a previous $fh not destroyed
my $ofhid = 'CAF::FileWriter '.refaddr($fh);

init_test();
$fh = CAF::FileWriter->open ($INC{"CAF/FileWriter.pm"}, log => $this_app);
$fh->close();

my $fhid = 'CAF::FileWriter '.refaddr($fh);

diag explain $this_app->{HISTORY}->{EVENTS};

# events since History enabled
#   new one initialised
#   on assignment to fh, old one destroyed, triggers close
#   close on new one
is_deeply($this_app->{HISTORY}->{EVENTS}, [
    {
        IDX => 0,
        ID => $fhid,
        REF => 'CAF::FileWriter',
        TS => 0,
        filename =>  $INC{"CAF/FileWriter.pm"},
        init => 1,
    },
    {
        IDX => 1,
        ID => $ofhid,
        REF => 'CAF::FileWriter',
        TS => 0,
        filename =>  $INC{"CAF/FileWriter.pm"},
        backup => undef,
        modified => undef,
        noaction => 1,
    },
    {
        IDX => 2,
        ID => $fhid,
        REF => 'CAF::FileWriter',
        TS => 0,
        filename =>  $INC{"CAF/FileWriter.pm"},
        backup => undef,
        modified => 0,
        noaction => 1,
    },
], "events added to history on init and close");

# legacy add_files: there were 2 closes, only last one is tracked
is(scalar(@{$this_app->{FILES}}), 1,
   "Files were recorded when the logger can add_files");

done_testing();
