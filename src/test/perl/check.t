use strict;
use warnings;

BEGIN {
    # remove the module path that is holding the temp LC mock
    # we actually want to run something here
    @INC = grep { $_ !~ m/resources$/ } @INC;
}

use LC::Exception qw (SUCCESS throw_error);

use Test::More;
use Test::MockModule;

use CAF::Object;
use CAF::Check;

use Test::Quattor::Object;

use FindBin qw($Bin);
use lib "$Bin/modules";
use mycheck;

use File::Path qw(mkpath rmtree);
use File::Basename qw(dirname);

$CAF::Object::NoAction = 1;

my $ec_check = $CAF::Check::EC;

my $obj = Test::Quattor::Object->new();

my $mock = Test::MockModule->new('CAF::Check');

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

my $mc = mycheck->new(log => $obj);

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

# Set the fail attribute, it should be reset
$mc->{fail} = 'somefailure';

# Inject an error, _function_catch should handle it gracefully (i.e. ignore it)
my $myerror = LC::Exception->new();
$myerror->reason('origexception');
$myerror->is_error(1);
$ec_check->error($myerror);

ok($ec_check->error(), "Error before _function_catch success_func");

is($mc->_function_catch($success_func, [qw(a b)], {c => 'd', e => 'f'}), 100,
   "_function_catch with success_func returns correct value");
is_deeply($args, [qw(a b)], "_func_catch passes arg arrayref correctly");
is_deeply($opts, {c => 'd', e => 'f'}, "_func_catch passes opt hashref correctly");

ok(! defined($mc->{fail}), "Fail attribute reset after success_func");
ok(! $ec_check->error(), "Error reset after success_func");


# Test failures/exception
# Not going to check args/opts
my $failure_func = sub {
    throw_error('failure_func failed', 'no real reason');
    return 200;
};

# Set the fail attribute, it should be reset
$mc->{fail} = 'somefailure';

# Inject an error, _function_catch should handle it gracefully (i.e. ignore it)
$myerror = LC::Exception->new();
$myerror->reason('origexception');
$myerror->is_error(1);
$ec_check->error($myerror);

ok($ec_check->error(), "Error before _function_catch failure_func");

ok(! defined($mc->_function_catch($failure_func)),
   "_function_catch with failure_func returns undef");

is($mc->{fail}, '*** failure_func failed: no real reason',
   "Fail attribute set after failure_func (and orig attribute reset)");
ok(! $ec_check->error(), "Error reset after failure_func, no error after failure");

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
    shift;
    push(@$func_catch_args, @_);
    return 100; # more nonsensical stuff but very usefull for testing
});

$mc->{fail} = undef;
is($mc->LC_Check('directory', [qw(a b c)], {optX => 'x', 'noaction' => 5, 'keeps_state' => 30}),
   100, "LC_Check returns value from _func_catch on known LC::Check dispatch");
is_deeply($noaction_args, [30], "keeps_state option passed to _get_noaction");
is_deeply($func_catch_args, [
              \&LC::Check::directory, # coderef to from the dispatch table
              [qw(a b c)],
              {optX => 'x', 'noaction' => 20} # keeps_state is removed; noaction overridden with value from _get_noaction
          ], "_func_args called with expected args");
ok(! defined($mc->{fail}), "No fail attribute set");


# Test calling unknown dispatch method
$func_catch_args = [];
ok(! defined($mc->LC_Check('no_lc_check_function')), # args are not relevant
   "failing LC_Check returns undef");

is_deeply($func_catch_args, [], "_func_catch not called");
is($mc->{fail}, "Unsupported LC::Check function no_lc_check_function",
   "fail attribute set on failure");


# Done, unmock for further tests
$mock->unmock('_get_noaction');
$mock->unmock('_function_catch');

=head2 directory/file/any exists

=cut

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


=head2 directory

=cut

$CAF::Object::NoAction = 0;

# add a/b/c to test mkdir -p behaviour
rmtree($basetest) if -d $basetest;
ok($mc->directory("$basetest/a/b/c"), "directory returns success");
ok($mc->directory_exists("$basetest/a/b/c"), "directory_exists true on directory with NoAction=0");

# Tests with NoAction
$CAF::Object::NoAction = 1;

# add a/b/c to test mkdir -p behaviour
rmtree($basetest) if -d $basetest;
ok($mc->directory("$basetest/a/b/c"), "directory returns success");
ok(! $mc->directory_exists("$basetest/a/b/c"), "directory_exists false on directory with NoAction=1");


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
ok($mc->directory_exists($cleanupdir1), "cleanupdirectory exists");

ok($mc->cleanup($cleanupfile1, ''), "cleanup testfile, no backup ok");
ok(! $mc->file_exists($cleanupfile1), "cleanup testfile does not exist anymore");

ok($mc->cleanup($cleanupdir1, ''), "cleanup directory, no backup ok");
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

ok($mc->cleanup($cleanupfile1, '.old'), "cleanup testfile, w backup ok");
ok(! $mc->file_exists($cleanupfile1), "cleanup testfile does not exist anymore w backup");
ok($mc->file_exists($cleanupfile1b), "cleanup backup testfile does exist w backup");
is(readfile($cleanupfile1b), 'ok', 'backup cleanupfile has content of testfile, so this is the new backup file');

ok($mc->cleanup($cleanupdir1, '.old'), "cleanup directory, w backup ok");
ok(! $mc->directory_exists($cleanupdir1), "cleanup testdir does not exist anymore w backup");
ok($mc->directory_exists("$cleanupdir1.old"), "cleanup backup testdir does exist w backup");
is(readfile("$cleanupdir1.old/file.old"), 'ok', 'backup file in backup dir has content of testfile, that old testdir backup file');

# Tests with NoAction
$CAF::Object::NoAction = 1;
rmtree($cleanupdir1) if -d $cleanupdir1;
makefile($cleanupfile1);

ok($mc->cleanup($cleanupfile1, '.old'), "cleanup testfile, w backup ok and NoAction");
ok($mc->file_exists($cleanupfile1), "cleanup testfile still exists w backup and NoAction");

ok($mc->cleanup($cleanupdir1, '.old'), "cleanup directory, w backup ok and NoAction");
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
# Set the fail attribute, it should be reset
$mc->{fail} = 'somefailure';

# Inject an error, getTree should handle it gracefully (i.e. ignore it)
$myerror = LC::Exception->new();
$myerror->reason('origexception');
$myerror->is_error(1);
$ec_check->error($myerror);

ok($ec_check->error(), "Error before directory creation");

ok($mc->directory("$basetest/a/b/c"), "directory returns success");

ok(! defined($mc->{fail}), "Fail attribute reset after succesful directory/LC_Check");
ok(! $ec_check->error(), "Error reset after directory creation");
ok($mc->directory_exists("$basetest/a/b/c"), "directory_exists true on directory");


rmtree($basetest) if -d $basetest;
makefile($basetestfile);

#
# Test failure
#
# Try to create dir on top of existing broken symlink.
ok(symlink("really_really_missing", $brokenlink), "broken symlink created");

ok(!$mc->directory_exists($brokenlink), "brokenlink is not a directory");

# Set the fail attribute, it should be reset
$mc->{fail} = 'somefailure';
is($mc->{fail}, 'somefailure', "Fail attribute set before directory");

# Inject an error, getTree should handle it gracefully (i.e. ignore it)
$myerror = LC::Exception->new();
$myerror->reason('origexception');
$myerror->is_error(1);
$ec_check->error($myerror);

ok($ec_check->error(), "Error set before directory creation");

ok(!defined($mc->directory("$brokenlink/exist")),
   "directory on broken symlink parent returns undef on failure");
is($mc->{fail}, '*** mkdir(target/test/check/broken_symlink, 0755): File exists',
   "Fail attribute set (and existing value reset)");
ok(! $ec_check->error(), "No errors after failed directory creation");
ok(! $mc->directory_exists("$brokenlink/exist"), "directory brokenlink/exist not created");
ok(! $mc->directory_exists($brokenlink), "brokenlink still not a directory");


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
# Set the fail attribute, it should be reset
$mc->{fail} = 'somefailure';
is($mc->{fail}, 'somefailure', "Fail attribute set before status (missing/noaction)");
ok(! $mc->file_exists($statusfile), "status testfile does not exists missing/noaction");
ok($mc->status($statusfile, mode => 0400),
   "status on missing file returns 1 on missing/noaction");
ok(! defined($mc->{fail}), "Fail attribute not set (and existing value reset) for missing status file and noaction");
ok(! $mc->file_exists($statusfile), "status testfile still does not exists missing/noaction");

# disable NoAction
$CAF::Object::NoAction = 0;

rmtree($basetest) if -d $basetest;
# Test non-existingfile
# Set the fail attribute, it should be reset
$mc->{fail} = 'somefailure';
is($mc->{fail}, 'somefailure', "Fail attribute set before missing/action");
ok(! $mc->file_exists($statusfile), "status testfile does not exists missing/action");
$res = $mc->status($statusfile, mode => 0400);
diag "return res ", explain $res;
ok(! defined($mc->status($statusfile, mode => 0400)),
   "status on missing file returns undef missing/action");
is($mc->{fail}, '*** lstat(target/test/check/status): No such file or directory',
   "Fail attribute set (and existing value reset) for missing status file and action");
ok(! $mc->file_exists($statusfile), "status testfile still does not exists missing/action");

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

ok($mc->status($statusfile, mode => 0400), "status returns changed with mode 0400 (noaction set)");
$mode = (stat($statusfile))[2] & 07777;
is($mode, 0755, "created statusfile still has mode 0755 (noaction set)");


# disable NoAction

$CAF::Object::NoAction = 0;

rmtree($basetest) if -d $basetest;

makefile($statusfile);
ok($mc->file_exists($statusfile), "status testfile exists");
chmod(0755, $statusfile);
# Stat returns type and permissions
$mode = (stat($statusfile))[2] & 07777;
is($mode, 0755, "created statusfile has mode 0755");


ok($mc->status($statusfile, mode => 0400), "status returns changed with mode 0400 (noaction set)");
$mode = (stat($statusfile))[2] & 07777;
is($mode, 0400, "created statusfile has mode 0400 (action set)");


# reenable NoAction
$CAF::Object::NoAction = 1;


done_testing();
