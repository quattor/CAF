use strict;
use warnings;

use Test::More;
use Test::MockModule;
$SIG{__WARN__} = sub {ok(0, "Perl warning: $_[0]");};

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


use FindBin qw($Bin);
use lib "$Bin/modules";
use testapp;
use CAF::Reporter qw($HISTORY);
use CAF::History qw($EVENTS);
use CAF::Object qw(CHANGED);
use Scalar::Util qw(refaddr);
use Errno qw(ENOENT);

use Test::Quattor::Object;

my $obj = Test::Quattor::Object->new();

use LC::Exception;
my $EC = LC::Exception::Context->new()->will_store_errors();


# El ingenioso hidalgo Don Quijote de La Mancha
use constant TEXT => <<EOF;
En un lugar de La Mancha, de cuyo nombre no quiero acordarme
no ha mucho tiempo que vivía un hidalgo de los de adarga antigua...
EOF

use constant FILENAME => "/my/test";

# $path and %opts are set via the dummy File/AtomicWrite module
# $text is the file_contents from dummy LC/File module
# file_changed is not used anymore (actual Text::Diff is used against the $text)
our ($path, $text, $text_throw, $text_from_file, $faw_die);
our %opts = ();

my ($log, $dir_exists, $dir_args, $dir_ec, $status_args, $status_ec);
my $str = '';
open ($log, ">", \$str);

my $report;
my $this_app = testapp->new ($0, qw (--verbose));

sub init_test
{
    $text = undef;
    $text_throw = undef;
    $text_from_file = undef;
    $faw_die = undef;
    $path = "";
    %opts = ();
    $report = 0;
    close($log);
    $str = '';
    open ($log, ">", \$str);
    $dir_exists = 0;
    $dir_args = undef;
    $dir_ec = 1;
    $status_args = undef;
    $status_ec = 1; # no error, but no change either
}

my $mock_history = Test::MockModule->new('CAF::History');
my $mock_path = Test::MockModule->new('CAF::Path');
$mock_path->mock('directory', sub {
    my $self = shift;
    $dir_args = \@_;
    $self->{fail} = "directory failed" if !$dir_ec;
    return $dir_ec;
});
$mock_path->mock('directory_exists', sub {$dir_exists++; return 0;});

$mock_path->mock('status', sub {
    my $self = shift;
    $status_args = \@_;
    $self->{fail} = "status failed" if !$status_ec;
    return $status_ec;
});

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
ok (!defined($opts{MKPATH}), "The file is created without MKPATH");
ok (!*$fh->{save},  "File marked not to be saved after closing");
is ($path, FILENAME, "The correct file is opened");
is($dir_exists, 1, "directory exists called once");
is_deeply($dir_args, ['/my', 'mode', 0755], "directory creation called with parent dir args");
ok(!defined $status_args, "status not called");

my @methods = qw(info verbose report debug warn error event is_verbose);
foreach my $method (@methods) {
    ok($fh->can($method), "FileWriter instance has $method method");
    # for event, a hash is expected, so pass a second argument
    # please don't ever use it like this
    ok(! defined($fh->$method("abc", $method eq 'event' ? 'def' : undef)), "conditional logger without log defined returns undef");
}

# test _read_contents


# test _read_contents ok
ok(! $EC->error(), "No previous error before _read_contents test");
my $fake_event = {};
$text = 'test read';
is($fh->_read_contents('somefile', event => $fake_event), 'test read',
    "_read_contents returns text from LC::File::file_contents");
is($text_from_file, 'somefile', '_read_contents passes filename to LC::File::file_contents');
is_deeply($fake_event, {}, "_read_contents event unmodified on success");
ok(! $EC->error(), "No error after success _read_contents test / before _read_contents failure test");

# test _read_contents fails with exception due to ENOENT and missing_ok
$text = 'test read fail missing ok';
$text_throw = ['failure reading missing ok', ENOENT];
is($fh->_read_contents('somefilefail', event => $fake_event, missing_ok => 1),
   'test read fail missing ok',
    "_read_contents returns LC::File::file_contents return value with missing_ok");
is_deeply($fake_event, {},
          "_read_contents event not modified on failure missing ok");
ok(! $EC->error(), "no error by _read_contents missing ok");

# test _read_contents fails with exception
$text = 'test read fail';
$text_throw = 'failure reading';
ok(! defined($fh->_read_contents('somefilefail', event => $fake_event)),
    "_read_contents failure returns undef");
is($text_from_file, 'somefilefail', '_read_contents passes filename to LC::File::file_contents on fail');
is_deeply($fake_event, {error => 'file_contents failure reading'}, "_read_contents event modified on failure");
ok($EC->error(), "old-style exception thrown by LC::File::file_contents rethrown by _read_contents");
is($EC->error->text, $fake_event->{error}, "exception message from LC::File::file_contents rethrown");
$EC->ignore_error();

# test _read_contents fails with exception due to ENOENT
$text = 'test read fail missing';
$text_throw = ['failure reading missing', ENOENT];
ok(! defined($fh->_read_contents('somefilefail', event => $fake_event)),
    "_read_contents failure missing returns undef");
is_deeply($fake_event, {error => 'file_contents failure reading missing'},
          "_read_contents event modified on failure missing");
ok($EC->error(), "old-style exception thrown by LC::File::file_contents rethrown by _read_contents missing");
is($EC->error->text, $fake_event->{error}, "exception message from LC::File::file_contents rethrown missing");
$EC->ignore_error();


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
ok(!defined $status_args, "status not called after cancel");

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
$str = '';
$fh->cancel();
like ($str, qr{Will not save file /\S+ \(cancelled\)}, "Cancel operation correctly logged");
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
ok(!defined $status_args, "status not called with options");

is($CAF::Object::NoAction, 0, "NoAction is set to 0");

init_test;
# already written file
$text = TEXT;
$fh = CAF::FileWriter->new (FILENAME, log => $this_app);
print $fh TEXT;
$fh->close();
is_deeply(\%opts, {}, "no modification, no call to file_write");
$re = "File " . FILENAME . " was not modified";
like($str, qr{^$re}m, "Writing same contents correctly reported");
is_deeply($status_args, [FILENAME, 'mode', oct(644)],
          "status called after close without content change and default mode");

# Not writing anything to $fh and close -> (new) empty file
init_test;
$fh = CAF::FileWriter->new (FILENAME, log => $this_app);
$text = 'abc';
$fh->close();
$re = "File " . FILENAME . " was modified";
like($str, qr{^$re}m, "Open/close file correctly reported");
is($opts{contents}, '', "Open/close file resets content");
is ($opts{mode}, 0644, "Checking options: correct default mode passed");


$CAF::Object::NoAction = 1;

init_test;
$fh = CAF::FileWriter->open (FILENAME, log => $this_app);
print $fh TEXT;
is ("$fh", TEXT, "Stringify works");
like ($fh, qr(En un lugar), "Regexp also works");
$fh->close();
is($CAF::Object::NoAction, 1, "NoAction is set to 1");
is(scalar keys %opts, 0, "NoAction=1: File::AtomicWrite file_write is not called");
ok(!defined $status_args, "status not called with options w NoAction=1");

# actions on closed file
ok(!$fh->opened(), "file is not opened anymore");
is($fh->stringify(), '', "stringify after close is empty string");
is("$fh", "", "stringification after close is empty string");
ok(! defined($fh->close()), "closing an already closed file returns undef");


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
like($str, qr{Changes to \S+:}, "Diff is reported (sensitive default false)");
ok($report, "Diff will be shown/reported even with noaction (sensitive default false)");

# sensitive
init_test();
$report = 0;
$fh = CAF::FileWriter->open ($INC{"CAF/FileWriter.pm"}, log => $this_app, sensitive => 1);
print $fh "hello, world with sensitive data\n";
$fh->close();
like($str, qr{Changes to \S+ are not reported due to sensitive content}, "Diff is not reported with sensitive=1");
ok(! $report, "Diff will not be shown/reported with sensitive=1");

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

# there's a previous closed $fh not destroyed
my $ofhidclosed = 'CAF::FileWriter '.refaddr($fh);

# destroy $fh
$fh = CAF::FileWriter->open ($INC{"CAF/FileWriter.pm"}, log => $this_app);
my $ofhidnotclosed = 'CAF::FileWriter '.refaddr($fh);

init_test();
$fh = CAF::FileWriter->open ($INC{"CAF/FileWriter.pm"}, log => $this_app);
$fh->close();

my $fhid = 'CAF::FileWriter '.refaddr($fh);

# sensitive
init_test();
my $sfh = CAF::FileWriter->open ($INC{"CAF/FileWriter.pm"}, log => $this_app, sensitive => 1);
print $sfh "weeeee\n";
$sfh->close();

my $sfhid = 'CAF::FileWriter '.refaddr($sfh);

diag explain $this_app->{$HISTORY}->{$EVENTS};

# events since History enabled
#   new one initialised
#   --> on assignment to fh, old closed one destroyed, does not trigger close
#   new one initialised
#   on assignment to fh, old one destroyed, triggers close
#   close on new one
#   close on sensitive new one
is_deeply($this_app->{$HISTORY}->{$EVENTS}, [
    {
        IDX => 0,
        ID => $ofhidnotclosed,
        REF => 'CAF::FileWriter',
        TS => 0,
        WHOAMI => 'testapp',
        filename =>  $INC{"CAF/FileWriter.pm"},
        init => 1,
    },
    {
        IDX => 1,
        ID => $fhid,
        REF => 'CAF::FileWriter',
        TS => 0,
        WHOAMI => 'testapp',
        filename =>  $INC{"CAF/FileWriter.pm"},
        init => 1,
    },
    {
        IDX => 2,
        ID => $ofhidnotclosed,
        REF => 'CAF::FileWriter',
        TS => 0,
        WHOAMI => 'testapp',
        changed => 1,
        diff => '',
        filename =>  $INC{"CAF/FileWriter.pm"},
        backup => undef,
        modified => 0,
        noaction => 1,
        save => 1,
    },
    {
        IDX => 3,
        ID => $fhid,
        REF => 'CAF::FileWriter',
        TS => 0,
        filename => $INC{"CAF/FileWriter.pm"},
        WHOAMI => 'testapp',
        backup => undef,
        modified => 0,
        changed => 1,
        diff => '',
        noaction => 1,
        save => 1,
    },
    {
        IDX => 4,
        ID => $sfhid,
        REF => 'CAF::FileWriter',
        TS => 0,
        WHOAMI => 'testapp',
        filename => $INC{"CAF/FileWriter.pm"},
        init => 1,
    },
    {
        IDX => 5,
        ID => $sfhid,
        REF => 'CAF::FileWriter',
        TS => 0,
        filename =>  $INC{"CAF/FileWriter.pm"},
        WHOAMI => 'testapp',
        backup => undef,
        modified => 0,
        changed => 1,
        noaction => 1,
        save => 1,
    },
], "events added to history on init and close");

# test failures
$CAF::Object::NoAction = 0;

init_test();
ok(! $EC->error(), "No previous error before failure check");
$faw_die = "special problem";
$text = '123';
$fh = CAF::FileWriter->open (FILENAME, log => $obj);
print $fh TEXT;
is ("$fh", TEXT, "Stringify works");
$fh->close();
ok($EC->error(), "old-style exception thrown");
like($EC->error->text, qr{^close AtomicWrite failed filename /my/test: File::AtomicWrite special problem at },
     "message from die converted in exception");
$EC->ignore_error();

init_test();
ok(! $EC->error(), "No previous error before failure check");
$dir_ec = 0;
$fh = CAF::FileWriter->open (FILENAME, log => $obj);
print $fh TEXT;
$fh->close();
ok($EC->error(), "old-style exception thrown on directory failure");
like($EC->error->text, qr{^close AtomicWrite failed filename /my/test: Failed to make parent directory /my:directory failed},
     "fail attribute from directory converted in exception");
$EC->ignore_error();

init_test();
ok(! $EC->error(), "No previous error before failure check");
$dir_ec = 0;
is($this_app->err_mkfile(FILENAME, 'something'),
   'close AtomicWrite failed filename /my/test: Failed to make parent directory /my:directory failed',
   'err_mkfile handles error throwing');
ok(! $EC->error(), "No error before err_mkfile");

done_testing();
