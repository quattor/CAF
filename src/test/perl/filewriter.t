# TODO
#    - test failures of write_file
#    - diffs with non-existing file
#       - what does file_contents return? undef + exception
#    - actual tests without LC or any mocking
#       - test creation of parent dir
#    - touch: open and close file with filewriter? no, reset file


use strict;
use warnings;

use Test::More;
$SIG{__WARN__} = sub {ok(0, "Perl warning: $_[0]");};

use FindBin qw($Bin);
use lib "$Bin/modules";
use testapp;
use CAF::Reporter qw($HISTORY);
use CAF::History qw($EVENTS);
use CAF::Object;
use Test::MockModule;
use Scalar::Util qw(refaddr);


# El ingenioso hidalgo Don Quijote de La Mancha
use constant TEXT => <<EOF;
En un lugar de La Mancha, de cuyo nombre no quiero acordarme
no ha mucho tiempo que vivía un hidalgo de los de adarga antigua...
EOF

use constant FILENAME => "/my/test";

# $path and %opts are set via the dummy File/AtomicWrite module
# $text is the file_contents from dummy LC/File module
# file_changed is not used anymore (actual Text::Diff is used against the $text)
our ($path, $text);
our %opts = ();

my ($log, $str);
open ($log, ">", \$str);

my $report;
my $this_app = testapp->new ($0, qw (--verbose));

sub init_test
{
    $text = undef;
    $path = "";
    %opts = ();
    $report = 0;
    close($log);
    open ($log, ">", \$str);
}

my $proc;
my $mock;
my $app;


BEGIN {
    $mock = Test::MockModule->new ("CAF::Process");
    # (Mocked) run is used for selinux restore call
    $mock->mock ("run", sub {
                     $proc = $_[0];
                     $? = 0;
                     return 1;
                });
    $app = Test::MockModule->new ('CAF::Application');
}

my $mock_history = Test::MockModule->new('CAF::History');

use CAF::FileWriter;

if ($^O eq 'linux') {
    isa_ok ($proc, "CAF::Process", "restorecon hook enabled at load time");
}

$this_app->config_reporter(logfile => $log);

init_test;
my $fh = CAF::FileWriter->new (FILENAME, mode => 0600);
print $fh TEXT;
ok (*$fh->{save}, "File marked to be saved");
$fh->close();
is ($opts{contents}, TEXT, "The file has the correct contents");
is ($opts{mode}, 0600, "The file is created with the correct permissions");
ok (!*$fh->{save},  "File marked not to be saved after closing");
is ($path, FILENAME, "The correct file is opened");

my @methods = qw(info verbose report debug warn error event is_verbose);
foreach my $method (@methods) {
    ok($fh->can($method), "FileWriter instance has $method method");
    # for event, a hash is expected, so pass a second argument
    # please don't ever use it like this
    ok(! defined($fh->$method("abc", $method eq 'event' ? 'def' : undef)), "conditional logger without log defined returns undef");
}


init_test;
$fh = CAF::FileWriter->new (FILENAME, mode => 0400);
print $fh TEXT;
$fh = "";
is ($opts{contents}, TEXT, "The file is written when the object is destroyed");
is ($opts{mode}, 0400, "The file gets the correct permissions when the object is destroyed");
ok(! defined($CAF::Object::NoAction), "NoAction is not defined");
is ($path, FILENAME, "Correct path opened on object destruction");

$CAF::Object::NoAction = 0;

init_test;
$fh = CAF::FileWriter->new (FILENAME);
print $fh TEXT;
$fh->cancel;
is (*$fh->{save}, 0, "File marked not to be saved");
$fh->close;
is ($path, "", "No file is opened when cancelling");
ok (!exists ($opts{contents}), "Nothing is written after cancel");

init_test;
$fh = CAF::FileWriter->new (
    FILENAME,
    mode => 0600,
    log => $this_app,
);
print $fh TEXT;
is ($str, "Opening file " . FILENAME . "\n",
    "Correct log message when creating the object");
$fh->close;
is ($opts{contents}, TEXT, "Correct contents written to the logged file");
is ($path, FILENAME, "Correct file opened with log");
my $re =  ".*File " . FILENAME . " was modified"; #
like($str, qr{$re},
     "Modified file correctly reported");
ok (!exists ($opts{LOG}), "No log information passed to File::atomicWrite::write_file");
$fh = CAF::FileWriter->new (FILENAME, log => $this_app);
$fh->cancel();
like ($str, qr{Not saving file /}, "Cancel operation correctly logged");
$fh->close();

init_test;
$fh = CAF::FileWriter->open (
    FILENAME,
    log => $this_app,
    backup => "foo",
    mode => 0400,
    owner => 100,
    group => 200,
    mtime => 1234567,
);
print $fh TEXT;
$fh->close();
is ($opts{backup}, "foo", "Checking options: correct backup option passed");
is ($opts{mode}, 0400, "Checking options: correct mode passed");
is ($opts{owner}, "100:200", "Checking options: correct owner/group passed as owner:group");
is ($opts{mtime}, 1234567, "Checking options: correct mtime passed");

is($CAF::Object::NoAction, 0, "NoAction is set to 0");

init_test;
# already written file
$text = TEXT;
$fh = CAF::FileWriter->new (FILENAME, log => $this_app);
print $fh TEXT;
$fh->close();
$re = "File " . FILENAME . " was not modified";
like($str, qr{^$re}m, "Writing same contents correctly reported");

# Not writing anything to $fh and close -> (new) empty file
init_test;
$fh = CAF::FileWriter->new (FILENAME, log => $this_app);
$text = 'abc';
$fh->close();
$re = "File " . FILENAME . " was modified";
like($str, qr{^$re}m, "Unused opened file correctly reported");

$CAF::Object::NoAction = 1;

init_test;
$fh = CAF::FileWriter->open (FILENAME, log => $this_app);
print $fh TEXT;
is ("$fh", TEXT, "Stringify works");
like ($fh, qr(En un lugar), "Regexp also works");
$fh->close();
is($CAF::Object::NoAction, 1, "NoAction is set to 1");
is(scalar keys %opts, 0, "NoAction=1: File::AtomicWrite file_write is not called");

init_test;
is($CAF::Object::NoAction, 1, "NoAction is set to 1 before keeps_state true");
$fh = CAF::FileWriter->open (FILENAME, log => $this_app, keeps_state => 1);
print $fh TEXT;
is ("$fh", TEXT, "Stringify works");
like ($fh, qr(En un lugar), "Regexp also works");
$fh->close();
is($CAF::Object::NoAction, 1, "NoAction is (still) set to 1 with keeps_state true");
is($opts{file}, FILENAME, "NoAction 1 and keeps_state true: File::AtomicWrite file_write is called");

# Check that the diff works
$app->mock('report', sub { $report = 1; });

$this_app->config_reporter(logfile => $log);
init_test();
$report = 0;
$fh = CAF::FileWriter->open ($INC{"CAF/FileWriter.pm"}, log => $this_app);
print $fh "hello, world\n";
$fh->close();
like($str, qr{Changes to \S+:}, "Diff is reported");
ok($report, "Diff will be shown/reported even with noaction");

# No diffs if no contents
init_test();
$fh->close();
unlike($str, qr{Changes to \S+:}, "Diff not reported on already closed file");

# No diffs printed if not verbose
$CAF::Reporter::_REP_SETUP->{VERBOSE} = 0;
init_test();
$fh = CAF::FileWriter->open ($INC{"CAF/FileWriter.pm"}, log => $this_app);
print $fh "hello world\n";
$fh->close();
is($report, 0, "Diff output is reported only with verbose");

# Test events via CAF::History

# no need to track time
$mock_history->mock('_now', 0);

# no history until now, thisapp doesn't init_history on new()
ok(! defined($this_app->{$HISTORY}), 'No history tracked this far');

$this_app->init_history(); # no instance tracking
ok(defined($this_app->{$HISTORY}), 'history tracked enabled');

# there's a previous $fh not destroyed
my $ofhid = 'CAF::FileWriter '.refaddr($fh);

init_test();
$fh = CAF::FileWriter->open ($INC{"CAF/FileWriter.pm"}, log => $this_app);
$fh->close();

my $fhid = 'CAF::FileWriter '.refaddr($fh);

#diag explain $this_app->{$HISTORY}->{$EVENTS};

# events since History enabled
#   new one initialised
#   on assignment to fh, old one destroyed, triggers close
#   close on new one
is_deeply($this_app->{$HISTORY}->{$EVENTS}, [
    {
        IDX => 0,
        ID => $fhid,
        REF => 'CAF::FileWriter',
        TS => 0,
        WHOAMI => 'testapp',
        filename =>  $INC{"CAF/FileWriter.pm"},
        init => 1,
    },
    {
        IDX => 1,
        ID => $ofhid,
        REF => 'CAF::FileWriter',
        TS => 0,
        WHOAMI => 'testapp',
        filename =>  $INC{"CAF/FileWriter.pm"},
        backup => undef,
        modified => 0,
        noaction => 1,
        save => 0,
    },
    {
        IDX => 2,
        ID => $fhid,
        REF => 'CAF::FileWriter',
        TS => 0,
        filename =>  $INC{"CAF/FileWriter.pm"},
        WHOAMI => 'testapp',
        backup => undef,
        modified => 0,
        changed => 1,
        diff => '',
        noaction => 1,
        save => 1,
    },
], "events added to history on init and close");

done_testing();
