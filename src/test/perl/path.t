use strict;
use warnings;

BEGIN {
    # remove the module path that is holding the temp LC mock
    # we actually want to run something here
    @INC = grep { $_ !~ m/resources$/ } @INC;
}

use LC::Exception qw (throw_error);

use Test::More;
use Test::MockModule;

use CAF::Object qw(SUCCESS CHANGED);
use CAF::Path;

use Test::Quattor::Object;

use FindBin qw($Bin);
use lib "$Bin/modules";
use mypath;

use File::Path qw(mkpath rmtree);
use File::Basename qw(dirname);

$CAF::Object::NoAction = 1;

my $ec_check = $CAF::Path::EC;

my $obj = Test::Quattor::Object->new();

my $mock = Test::MockModule->new('CAF::Path');

# cannot use mocked filewriter
sub makefile
{
    my $fn = shift;
    my $dir = dirname($fn);
    mkpath $dir if ! -d $dir;
    open(FH, ">$fn");
    print FH (shift || "ok");
    close(FH);
}

sub readfile
{
    open(FH, shift);
    my $txt = join('', <FH>);
    close(FH);
    return $txt;
}

my $basetest = 'target/test/check';
my $basetestfile = "$basetest/file";
my $brokenlink = "$basetest/broken_symlink";
my $filelink = "$basetest/file_symlink";
my $dirlink = "$basetest/directory_symlink";

my $mc = mypath->new(log => $obj);

=head2 _get_noaction

=cut

$CAF::Object::NoAction = 0;

ok(! $mc->_get_noaction(), "_get_noaction returns false with CAF::Object::NoAction=0 and no keeps_state");
ok(! $mc->_get_noaction(0), "_get_noaction returns false with CAF::Object::NoAction=0 and keeps_state false");
ok(! $mc->_get_noaction(1), "_get_noaction returns false with CAF::Object::NoAction=0 and keeps_state true");

$CAF::Object::NoAction = 1;

ok($mc->_get_noaction(), "_get_noaction returns true with CAF::Object::NoAction=1 and no keeps_state");
ok($mc->_get_noaction(0), "_get_noaction returns true with CAF::Object::NoAction=1 and keeps_state false");
ok(! $mc->_get_noaction(1), "_get_noaction returns false with CAF::Object::NoAction=1 and keeps_state true");

=head2 _reset_exception_fail

=cut

my $exception_reset = 0;

sub init_exception
{
    my ($msg) = @_;
    $exception_reset = 0;

    # Set the fail attribute, it should be reset
    $mc->{fail} = "origfailure $msg";

    # Inject an error, _function_catch should handle it gracefully (i.e. ignore it)
    my $myerror = LC::Exception->new();
    $myerror->reason("origexception $msg");
    $myerror->is_error(1);
    $ec_check->error($myerror);

    ok($ec_check->error(), "Error before $msg");
}

sub verify_exception
{
    my ($msg, $fail, $expected_reset, $noreset) = @_;
    $expected_reset = 1 if (! defined($expected_reset));
    is($exception_reset, $expected_reset, "exception_reset called $expected_reset after $msg");
    if ($noreset) {
        ok($ec_check->error(), "Error not reset after $msg");
    } else {
        ok(! $ec_check->error(), "Error reset after $msg");
    };
    if ($noreset) {
        like($mc->{fail}, qr{^origfailure }, "Fail attribute matches originalfailure on noreset after $msg");
    } elsif ($fail) {
        like($mc->{fail}, qr{$fail}, "Fail attribute matches $fail after $msg");
        unlike($mc->{fail}, qr{origfailure}, "original fail attribute reset");
    } else {
        ok(! defined($mc->{fail}), "Fail attribute reset after $msg");
    };
};

init_exception("test _reset_exception_fail");

ok($mc->_reset_exception_fail(), "_reset_exception_fail returns SUCCESS");

# expected_reset is 0 here, because it's not mocked yet
verify_exception("test _reset_exception_fail", 0, 0);

# Continue with mocking _reset_exception_fail
$mock->mock('_reset_exception_fail', sub {
    $exception_reset += 1;
    my $init = $mock->original("_reset_exception_fail");
    return &$init(@_);
});


=head2 _function_catch

=cut

my $args = [];
my $opts = {};

my $success_func = sub {
    my ($arg1, $arg2, %opts) = @_;
    push(@$args, $arg1, $arg2);
    while (my ($k, $v) = each %opts) {
        $opts->{$k} = $v;
    };
    return 100;
};

# Empty args and opts refs
$args = [];
$opts = {};

init_exception("_function_catch success");

is($mc->_function_catch($success_func, [qw(a b)], {c => 'd', e => 'f'}), 100,
   "_function_catch with success_func returns correct value");
is_deeply($args, [qw(a b)], "_func_catch passes arg arrayref correctly");
is_deeply($opts, {c => 'd', e => 'f'}, "_func_catch passes opt hashref correctly");

verify_exception("_function_catch success");

# Test failures/exception
# Not going to check args/opts
my $failure_func = sub {
    throw_error('failure_func failed', 'no real reason');
    return 200;
};

init_exception("_function_catch fail");

ok(! defined($mc->_function_catch($failure_func)),
   "_function_catch with failure_func returns undef");

verify_exception("_function_catch fail", '\*\*\* failure_func failed: no real reason');

=head2 _safe_eval

=cut

my $funcref = sub {
    my ($ok, %opts) = @_;
    if ($ok) {
        return "hooray $opts{test}";
    } else {
        die "bad day today $opts{test}";
    }
};


init_exception("_safe_eval ok");

is($mc->_safe_eval($funcref, [1], {test => 123}, "eval fail", "eval ok"), "hooray 123",
   "_safe_eval with non-die function returns returnvalue");

verify_exception("_safe_eval ok");

init_exception("_safe_eval fail");

ok(! defined($mc->_safe_eval($funcref, [0], {test => 123}, "eval fail", "eval ok")),
   "_safe_eval with die function returns undef");

verify_exception("_safe_eval fail", '^eval fail: bad day today 123');

=head2 LC_Check

=cut

# for simplicity we are going to mock _function_catch and _get_noaction

my $noaction_args = [];
my $func_catch_args = [];
my $fc_val;
$mock->mock('_get_noaction', sub {
    shift;
    push (@$noaction_args, shift);
    return 20; # non-sensical value; but clear return value for testing
});
$mock->mock('_function_catch', sub {
    my $self = shift;
    $self->_reset_exception_fail();
    push(@$func_catch_args, @_);
    return 100; # more nonsensical stuff but very usefull for testing
});

init_exception("LC_Check mocked directory dispatch");

is($mc->LC_Check('directory', [qw(a b c)], {optX => 'x', 'noaction' => 5, 'keeps_state' => 30}),
   100, "LC_Check returns value from _func_catch on known LC::Check dispatch");
is_deeply($noaction_args, [30], "keeps_state option passed to _get_noaction");
is_deeply($func_catch_args, [
              \&LC::Check::directory, # coderef to from the dispatch table
              [qw(a b c)],
              {optX => 'x', 'noaction' => 20} # keeps_state is removed; noaction overridden with value from _get_noaction
          ], "_func_args called with expected args");

verify_exception("LC_Check mocked directory dispatch");



# Test calling unknown dispatch method
init_exception("LC_Check unknown dispatch");
$func_catch_args = [];
ok(! defined($mc->LC_Check('no_lc_check_function')), # args are not relevant
   "failing LC_Check returns undef");

is_deeply($func_catch_args, [], "_func_catch not called");
is($mc->{fail}, "Unsupported LC::Check function no_lc_check_function",
   "fail attribute set on unknown dispatch failure");
# so no point in running verify_excpetion
is($exception_reset, 0, "exception reset is not called when handling unknown dispatch");
ok($mc->_reset_exception_fail(), "_reset_exception_fail after unknown dispatch");

# Done, unmock for further tests
$mock->unmock('_get_noaction');
$mock->unmock('_function_catch');

=head2 directory/file/any exists

=cut

init_exception("existence tests");

# Tests without NoAction
$CAF::Object::NoAction = 0;

rmtree if -d $basetest;
ok(! $mc->directory_exists($basetest), "directory_exists false on missing directory");
ok(! $mc->file_exists($basetest), "file_exists false on missing directory");
ok(! $mc->any_exists($basetest), "any_exists false on missing directory");

ok(! $mc->directory_exists($basetestfile), "directory_exists false on missing file");
ok(! $mc->file_exists($basetestfile), "file_exists false on missing file");
ok(! $mc->any_exists($basetestfile), "any_exists false on missing file");

makefile($basetestfile);

ok($mc->directory_exists($basetest), "directory_exists true on created directory");
ok($mc->any_exists($basetest), "any_exists true on created directory");
ok(! $mc->file_exists($basetest), "file_exists false on created directory");

ok(! $mc->directory_exists($basetestfile), "directory_exists false on created file");
ok($mc->any_exists($basetestfile), "any_exists true on created file");
ok($mc->file_exists($basetestfile), "file_exists true on created file");

# Test (broken) symlink and _exsists methods

ok(symlink("really_really_missing", $brokenlink), "broken symlink created");
makefile("$basetest/tgtdir/tgtfile");
ok(symlink("tgtdir", $dirlink), "directory symlink created");
ok(symlink("tgtdir/tgtfile", $filelink), "file symlink created");

ok(! $mc->directory_exists($brokenlink), "directory_exists false on brokenlink");
ok(! $mc->file_exists($brokenlink), "file_exists false on brokenlink");
ok($mc->any_exists($brokenlink), "any_exists true on brokenlink");

ok($mc->directory_exists($dirlink), "directory_exists true on dirlink");
ok(! $mc->file_exists($dirlink), "file_exists false on dirlink");
ok($mc->any_exists($dirlink), "any_exists true on dirlink");

ok(! $mc->directory_exists($filelink), "directory_exists false on filelink");
ok($mc->file_exists($filelink), "file_exists true on filelink");
ok($mc->any_exists($filelink), "any_exists true on filelink");


# noreset=1
verify_exception("existence tests do not reset exception/fail", "origfailure", 0, 1);
ok($mc->_reset_exception_fail(), "_reset_exception_fail after existence tests");


=head2 directory

=cut

$CAF::Object::NoAction = 0;

# directory: name to create
# msg: to add to the test messages
# expected: return value (undef means CHANGED)
# notcreated: not created
# tmp: is tempdir
sub verify_directory
{
    my ($directory, $msg, $expected, $notcreated, $tmp) = @_;

    $expected = CHANGED if ! defined($expected);

    # Set mtime to check status
    my $mtime = 123456789; # Thu Nov 29 22:33:09 CET 1973
    my $dirres = $mc->directory($directory, temp => $tmp, mtime => $mtime);
    my $dir_exists = $mc->directory_exists($dirres);

    if ($notcreated) {
        ok(! $dir_exists, "directory_exists false on directory $msg");
    } else {
        ok($dir_exists, "directory_exists true on directory $msg");
        is((stat($dirres))[9], $mtime, "mtime set via status on directory $msg");
    }

    if ($tmp) {
        my $pat = '^'.$directory;
        # basic, needs further tests
        $pat =~ s/X+$//; # cut off to be templated patterns
        like($dirres, qr{$pat}, "temporary directory returns matching directory name as string value $msg");
        ok($dirres ne $directory, "temporary directory does not equal original template directory name as string value $msg");
        ok(! $mc->directory_exists($directory), "orignal template directory_exists true on directory $msg");
    } else {
        ok($dirres eq $directory, "directory returns directory name as string value $msg");
    }
    ok($dirres == $expected, "directory returns $expected (as integer value) $msg");

    return $dirres;
}

# add a/b/c to test mkdir -p behaviour
rmtree($basetest) if -d $basetest;
my $testdir = "$basetest/a/b/c";
verify_directory($testdir, "directory NoAction=0", CHANGED);
verify_directory($testdir, "directory NoAction=0 2nd time", SUCCESS);

# Tests with NoAction
$CAF::Object::NoAction = 1;

# add a/b/c to test mkdir -p behaviour
rmtree($basetest) if -d $basetest;
verify_directory($testdir, "directory NoAction=1", CHANGED, 1);
# as noaction doesn't do anything, it will keep changing the directory
verify_directory($testdir, "directory NoAction=1 2nd time", CHANGED, 1);

=head2 temporary directory creation

=cut


$CAF::Object::NoAction = 0;

# add a/b/c to test mkdir -p behaviour
rmtree($basetest) if -d $basetest;
$testdir = "$basetest/a/b/c-X";
my $pat = '^'.$basetest.'/a/b/c-\w{5}$';
my $tempdir = verify_directory($testdir, "temporary dir NoAction=0", CHANGED, undef, 1);
like($tempdir, qr{$pat}, "directory returns padded temp directory name with NoAction=0");
unlike($tempdir, qr{c-X{5}$}, "temp directory templated padded Xs with NoAction=0");

# Tests with NoAction
$CAF::Object::NoAction = 1;

# add a/b/c to test mkdir -p behaviour
rmtree($basetest) if -d $basetest;
$pat = '^'.$basetest.'/a/b/c-X{5}$';
$tempdir = $tempdir = verify_directory($testdir, "temporary dir NoAction=1", CHANGED, 1, 1);
like($tempdir, qr{$pat}, "directory returns padded non-templated temp directory name with NoAction=1");

# reenable NoAction
$CAF::Object::NoAction = 1;

=head2 cleanup

=cut

# Tests without NoAction
$CAF::Object::NoAction = 0;

# test with dir and file, without backup
my $cleanupdir1 = "$basetest/cleanup1";
my $cleanupfile1 = "$cleanupdir1/file";
my $cleanupfile1b = "$cleanupfile1.old";

rmtree($cleanupdir1) if -d $cleanupdir1;
makefile($cleanupfile1);
ok($mc->file_exists($cleanupfile1), "cleanup testfile exists");
ok($mc->directory_exists($cleanupdir1), "cleanup testdir exists");

is($mc->cleanup($cleanupfile1, ''), CHANGED,"cleanup testfile, no backup ok");
ok(! $mc->file_exists($cleanupfile1), "cleanup testfile does not exist anymore");

is($mc->cleanup($cleanupdir1, ''), CHANGED, "cleanup testdir, no backup ok");
ok(! $mc->directory_exists($cleanupdir1), "cleanup testdir does not exist anymore");

# test with dir and file, without backup
rmtree($cleanupdir1) if -d $cleanupdir1;
makefile($cleanupfile1);
is(readfile($cleanupfile1), 'ok', 'cleanupfile has expected content');
makefile("$cleanupfile1b", "woohoo");
is(readfile($cleanupfile1b), 'woohoo', 'backup cleanupfile has expected content');

ok($mc->file_exists($cleanupfile1), "cleanup testfile exists w backup");
ok($mc->file_exists($cleanupfile1b), "cleanup backup testfile already exists w backup");
ok($mc->directory_exists($cleanupdir1), "cleanupdirectory exists w backup");

is($mc->cleanup($cleanupfile1, '.old'), CHANGED, "cleanup testfile, w backup ok");
ok(! $mc->file_exists($cleanupfile1), "cleanup testfile does not exist anymore w backup");
ok($mc->file_exists($cleanupfile1b), "cleanup backup testfile does exist w backup");
is(readfile($cleanupfile1b), 'ok', 'backup cleanupfile has content of testfile, so this is the new backup file');

is($mc->cleanup($cleanupfile1, '.old'), SUCCESS, "cleanup missing testfile SUCCESS");

is($mc->cleanup($cleanupdir1, '.old'), CHANGED, "cleanup directory, w backup ok");
ok(! $mc->directory_exists($cleanupdir1), "cleanup testdir does not exist anymore w backup");
ok($mc->directory_exists("$cleanupdir1.old"), "cleanup backup testdir does exist w backup");
is(readfile("$cleanupdir1.old/file.old"), 'ok', 'backup file in backup dir has content of testfile, that old testdir backup file');

is($mc->cleanup($cleanupdir1, '.old'), SUCCESS, "cleanup missing testdir SUCCESS");

# Tests with NoAction
$CAF::Object::NoAction = 1;
rmtree($cleanupdir1) if -d $cleanupdir1;
makefile($cleanupfile1);

is($mc->cleanup($cleanupfile1, '.old'), CHANGED,"cleanup testfile, w backup ok and NoAction");
ok($mc->file_exists($cleanupfile1), "cleanup testfile still exists w backup and NoAction");

is($mc->cleanup($cleanupdir1, '.old'), CHANGED, "cleanup directory, w backup ok and NoAction");
ok($mc->directory_exists($cleanupdir1), "cleanup testdir still exists w backup and NoAction");


# reenable NoAction
$CAF::Object::NoAction = 1;

=head2 Failures

Using directory to test LC_Check / _function_catch

=cut


$CAF::Object::NoAction = 0;

#
# Test success / resetting of previous failures
#

# add a/b/c to test mkdir -p behaviour
rmtree($basetest) if -d $basetest;

$testdir = "$basetest/a/b/c";
init_exception("directory creation NoAction=0");

verify_directory($testdir, "directory exception test");

# exception reset called 3 times: start, LC_Check and status
verify_exception("directory creation NoAction=0", undef, 3);


rmtree($basetest) if -d $basetest;
makefile($basetestfile);

#
# Test failure
#
# Try to create dir on top of existing broken symlink.
ok(symlink("really_really_missing", $brokenlink), "broken symlink created 1");

ok(!$mc->directory_exists($brokenlink), "brokenlink is not a directory");

init_exception("directory creation failure NoAction=0");

ok(!defined($mc->directory("$brokenlink/exist")),
   "directory on broken symlink parent returns undef on failure");

# Called 2 times: init and LC_Check (no status)
verify_exception("directory creation failure NoAction=0",
                 '\*\*\* mkdir\(target/test/check/broken_symlink, 0755\): File exists', 2);
ok(! $mc->directory_exists("$brokenlink/exist"), "directory brokenlink/exist not created");
ok(! $mc->directory_exists($brokenlink), "brokenlink still not a directory");


# trigger tempdir failure, impossible subdir
# reset original exception also in this case

rmtree($basetest) if -d $basetest;
makefile($basetestfile);

# Try to create dir on top of existing broken symlink.
ok(symlink("really_really_missing", $brokenlink), "broken symlink created 2");

ok(!$mc->directory_exists($brokenlink), "brokenlink is not a directory 2");

init_exception("temp directory creation failure NoAction=0 subdir");

ok(!defined($mc->directory("$brokenlink/sub/exist-X", temp => 1)),
   "temp directory on broken symlink parent returns undef on failure missing subdir");
# called 3 times: init, 2 times with creation of subdir via failing directory
verify_exception("temp directory creation failure NoAction=0 subdir",
                 'Failed to create basedir for temporary directory target/test/check/broken_symlink/sub/exist-XXXXX', 3);
ok(! $mc->directory_exists("$brokenlink/exist"), "directory brokenlink/exist not created 2");
ok(! $mc->directory_exists($brokenlink), "brokenlink still not a directory 2");

# trigger tempdir failure, make tempdir in non-writeable directory
# reset original exception also in this case

rmtree($basetest) if -d $basetest;
makefile($basetestfile);


$tempdir = "$basetest/sub/exist-X";

my $basetempdir = dirname($tempdir);
# use this to create the subdir
ok($mc->directory($tempdir), "Testdir template exists");
ok($mc->directory_exists($basetempdir), "Testdir basedir exists");

# remove all permissions on basedir
chmod(0000, $basetempdir);

init_exception("temp directory creation failure NoAction=0 permission");

ok(!defined($mc->directory($tempdir, temp => 1)),
   "temp directory on broken symlink parent returns undef on failure tempdir");

# called 2 times: init and _safe_eval
verify_exception("temp directory creation failure NoAction=0 permission",
                 '^Failed to create temporary directory target/test/check/sub/exist-XXXXX: Error in tempdir\(\) using target/test/check/sub/exist-XXXXX: Could not create directory target/test/check/sub/exist-\w{5}: Permission denied at', 2);

ok(! $mc->directory_exists("$brokenlink/exist"), "temp directory brokenlink/exist not created 3");
ok(! $mc->directory_exists($brokenlink), "temp brokenlink still not a directory 3");

# reset write bits for removal
chmod(0700, $basetempdir);


# reenable NoAction
$CAF::Object::NoAction = 1;

=head2 status missing file

=cut

my $statusfile = "$basetest/status";
my ($mode, $res);

# enable NoAction
$CAF::Object::NoAction = 1;


rmtree($basetest) if -d $basetest;
# Test non-existingfile

init_exception("status (missing/noaction=1)");

ok(! $mc->file_exists($statusfile), "status testfile does not exists missing/noaction=1");
is($mc->status($statusfile, mode => 0400), CHANGED,
   "status on missing file returns success on missing/noaction=1");
verify_exception("status (missing/noaction=1)");

ok(! $mc->file_exists($statusfile), "status testfile still does not exists missing/noaction=1");

# disable NoAction
$CAF::Object::NoAction = 0;

rmtree($basetest) if -d $basetest;
# Test non-existingfile
init_exception("status (missing/noaction=0)");
ok(! $mc->file_exists($statusfile), "status testfile does not exists missing/noaction=0");
ok(! defined($mc->status($statusfile, mode => 0400)),
   "status on missing file returns undef missing/noaction=0");
verify_exception("status (missing/noaction=0)",
                 '\*\*\* lstat\(target/test/check/status\): No such file or directory');
ok(! $mc->file_exists($statusfile), "status testfile still does not exists missing/noaction=0");

=head2 status existing file

=cut

rmtree($basetest) if -d $basetest;

makefile($statusfile);
ok($mc->file_exists($statusfile), "status testfile exists");
chmod(0755, $statusfile);
# Stat returns type and permissions
$mode = (stat($statusfile))[2] & 07777;
is($mode, 0755, "created statusfile has mode 0755");


# enable NoAction
$CAF::Object::NoAction = 1;

rmtree($basetest) if -d $basetest;

makefile($statusfile);
ok($mc->file_exists($statusfile), "status testfile exists");
chmod(0755, $statusfile);
# Stat returns type and permissions
$mode = (stat($statusfile))[2] & 07777;
is($mode, 0755, "created statusfile has mode 0755");

is($mc->status($statusfile, mode => 0400), CHANGED, "status returns changed with mode 0400 (noaction=1)");
$mode = (stat($statusfile))[2] & 07777;
is($mode, 0755, "created statusfile still has mode 0755 (noaction=1)");

is($mc->status($statusfile, mode => 0400), CHANGED, "status returns changed with mode 0400 (noaction=1) 2nd time");

# disable NoAction

$CAF::Object::NoAction = 0;

rmtree($basetest) if -d $basetest;

makefile($statusfile);
ok($mc->file_exists($statusfile), "status testfile exists");
chmod(0755, $statusfile);
# Stat returns type and permissions
$mode = (stat($statusfile))[2] & 07777;
is($mode, 0755, "created statusfile has mode 0755");


is($mc->status($statusfile, mode => 0400), CHANGED, "status returns changed with mode 0400 (noaction=0)");
$mode = (stat($statusfile))[2] & 07777;
is($mode, 0400, "created statusfile has mode 0400 (noaction=0)");

is($mc->status($statusfile, mode => 0400), SUCCESS,
   "2nd status returns success/not changed with mode 0400 (noaction=0)");


# reenable NoAction
$CAF::Object::NoAction = 1;


done_testing();
