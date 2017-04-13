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
use Cwd;

use CAF::Object qw(SUCCESS CHANGED);
use CAF::Path;

use Test::Quattor::Object;

use FindBin qw($Bin);
use lib "$Bin/modules";
use mypath;
use Test::Quattor::Filetools qw(writefile readfile);;

use File::Path qw(mkpath rmtree);
use File::Basename qw(dirname);

my $ec_check = $CAF::Path::EC;

my $obj = Test::Quattor::Object->new();

my $mock = Test::MockModule->new('CAF::Path');
my $mockobj = Test::MockModule->new('CAF::Object');

# return global value instead of the one set during init
$mockobj->mock('noAction', sub {return $CAF::Object::NoAction});


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
my $symlink_call_count = 0;
my $hardlink_call_count = 0;
my $function_catch_call_count = 0;

# init_exception() and verify_exception() functions work in pair. They allow to register a message
# in 'fail' attribute at the beginning of a test section and to verify if new (unexpected) exceptions
# where raised during the test section. To reset the 'fail' attribute after verify_exception(),
# call _reset_exception_fail(). init_exception() implicitely resets the 'fail' attribute and also
# reset to 0 the count of calls to _reset_exception_fail().
sub init_exception
{
    my ($msg) = @_;
    $exception_reset = 0;
    $symlink_call_count = 0;
    $hardlink_call_count = 0;
    $function_catch_call_count = 0;

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
    is($exception_reset, $expected_reset, "_reset_exception_fail called $expected_reset times after $msg");
    if ($noreset) {
        ok($ec_check->error(), "Error not reset after $msg");
    } else {
        ok(! $ec_check->error(), "Error reset after $msg");
    };
    if ($noreset && defined($mc->{fail})) {
        like($mc->{fail}, qr{^origfailure }, "Fail attribute matches originalfailure on noreset after $msg");
    } elsif ($fail && defined($mc->{fail})) {
        like($mc->{fail}, qr{$fail}, "Fail attribute matches $fail after $msg");
        unlike($mc->{fail}, qr{origfailure}, "original fail attribute reset");
    } elsif ( ! $noreset ) {
        ok(! defined($mc->{fail}), "Fail attribute reset after $msg");
    } else {
        ok(0, "internal test error: unexpected undefined fail attribute") if (! defined($mc->{fail}));
    };
};

init_exception("test _reset_exception_fail");

ok($mc->_reset_exception_fail(), "_reset_exception_fail returns SUCCESS");

# expected_reset is 0 here, because it's not mocked yet
verify_exception("test _reset_exception_fail", 0, 0);

# Continue with mocking _reset_exception_fail
$mock->mock('_reset_exception_fail', sub {
    $exception_reset += 1;
    diag "mocked _reset_exception_fail $exception_reset times ".(scalar @_ == 2 ? $_[1] : '');
    my $init = $mock->original("_reset_exception_fail");
    return &$init(@_);
});

# Mocked symlink() and hardlink() to count calls

$mock->mock('symlink', sub {
    $symlink_call_count += 1;
    my $symlink_orig = $mock->original('symlink');
    return &$symlink_orig(@_);
});

$mock->mock('hardlink', sub {
    $hardlink_call_count += 1;
    my $hardlink_orig = $mock->original('hardlink');
    return &$hardlink_orig(@_);
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
is_deeply($args, [qw(a b)], "_function_catch passes arg arrayref correctly");
is_deeply($opts, {c => 'd', e => 'f'}, "_function_catch passes opt hashref correctly");

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
              {optX => 'x', 'noaction' => 20, silent => 0} # keeps_state is removed; noaction overridden with value from _get_noaction; silent=0 with noaction
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

# Done, unmock _get_noaction and mock _function_catch differently for for further tests
$mock->unmock('_get_noaction');

# New mocked _function_catch() allow to count the number of calls to computing
# the expected number of exception resets
$mock->mock('_function_catch', sub {
    $function_catch_call_count += 1;
    my $function_catch_orig = $mock->original('_function_catch');
    return &$function_catch_orig(@_);
});


=head2 _untaint_path

=cut

$mc->{fail} = undef;
ok(! defined($mc->_untaint_path("", "empty")), "failed to untaint empty string");
is($mc->{fail}, "Failed to untaint empty: path ",
   "failed to untaint empty string fail attribute set with message");

$mc->{fail} = undef;
ok(! defined($mc->_untaint_path("abc\0eef", "null")), "failed to untaint string with null");
is($mc->{fail}, "Failed to untaint null: path abc\0eef",
   "failed to untaint string with null fail attribute set with message");


$mc->{fail} = undef;
is($mc->_untaint_path("abc", "ok"), "abc", "untaint ok");
ok(! defined($mc->{fail}), "no fail attribute set with ok path");


=head2 directory/file/any exists on files and directories

=cut

init_exception("existence tests (file/directory)");

# Tests without NoAction
$CAF::Object::NoAction = 0;

rmtree ($basetest) if -d $basetest;
ok(! $mc->directory_exists($basetest), "directory_exists false on missing directory");
ok(! $mc->file_exists($basetest), "file_exists false on missing directory");
ok(! $mc->any_exists($basetest), "any_exists false on missing directory");
ok(! $mc->is_symlink($basetest), "is_symlink false on missing directory");
ok(! $mc->has_hardlinks($basetest), "has_hardlinks false on missing directory");
is($mc->is_hardlink($basetest, $basetest), undef, "is_hardlink false with missing directories");

ok(! $mc->directory_exists($basetestfile), "directory_exists false on missing file");
ok(! $mc->file_exists($basetestfile), "file_exists false on missing file");
ok(! $mc->any_exists($basetestfile), "any_exists false on missing file");
ok(! $mc->is_symlink($basetestfile), "is_symlink false on missing file");
ok(! $mc->has_hardlinks($basetestfile), "has_hardlinks false on missing file");
is($mc->is_hardlink($basetestfile, $basetestfile), undef, "is_hardlink false with missing files");

writefile($basetestfile);
my $basetestfile2 = $basetestfile . "_2";
writefile($basetestfile2);

ok($mc->directory_exists($basetest), "directory_exists true on created directory");
ok($mc->any_exists($basetest), "any_exists true on created directory");
ok(! $mc->file_exists($basetest), "file_exists false on created directory");
ok(! $mc->is_symlink($basetest), "is_symlink false on created directory");
ok(! $mc->has_hardlinks($basetest), "has_hardlinks false on created directory");
is($mc->is_hardlink($basetest, $basetest), undef, "is_hardlink false with created directories");

ok(! $mc->directory_exists($basetestfile), "directory_exists false on created file");
ok($mc->any_exists($basetestfile), "any_exists true on created file");
ok($mc->file_exists($basetestfile), "file_exists true on created file");
ok(! $mc->is_symlink($basetestfile), "is_symlink false on created file");
ok(! $mc->has_hardlinks($basetestfile), "has_hardlinks false on created file");
is($mc->is_hardlink($basetestfile, $basetestfile), 0, "is_hardlink false (same file compared)");
is($mc->is_hardlink($basetestfile, $basetestfile2), 0, "is_hardlink false with non-hardlinked files");

# noreset=1
verify_exception("existence tests (file/directory)", undef, 0, 1);
ok($mc->_reset_exception_fail(), "_reset_exception_fail after existence tests (file/directory)");


=head2 symlink/hardlink creation/update/test

=cut

# Test symlink creation

# Function to do the ok()/is() pair, taking into account NoAction flag
sub check_symlink {
    my ($mc, $target, $link_path, $expected_status) = @_;
    my $noaction = $mc->_get_noaction();

    my $ok_msg;
    if ( $noaction ) {
        $ok_msg = "$link_path symlink not created (NoAction set)";
    } else {
        $ok_msg = "$link_path is " . ($expected_status == CHANGED ? "" : "already ") . "a symlink";
    }
    my $target_msg = "$link_path symlink has the expected " . ($expected_status == CHANGED ? "changed " : "") . "target ($target)";

    # Test if symlink was created or not according to NoAction flag
    my $ok_condition;
    if ( $noaction ) {
        $ok_condition = ! $mc->any_exists($link_path);
    } else {
        $ok_condition = $mc->is_symlink($link_path);
    }
    ok($ok_condition, $ok_msg);

    is(readlink($link_path), $target, $target_msg) unless $noaction;
};

init_exception("symlink tests");

rmtree ($basetest) if -d $basetest;
my $target_directory = "tgtdir";
my $target_file1 = "tgtfile1";
my $target_file2 = "$basetest/$target_directory/tgtfile2";
writefile("$basetest/$target_file1");
writefile($target_file2);
my %opts;

# Symlink creations
for $CAF::Object::NoAction (1,0) {
    is($mc->symlink($target_directory, $dirlink), CHANGED, "directory symlink created");
    check_symlink($mc, $target_directory, $dirlink, CHANGED);
    is($mc->symlink($target_file2, $filelink), CHANGED, "file symlink created");
    check_symlink($mc, $target_file2, $filelink, CHANGED);
}

# Valid symlink updates
# The following tests make no sens if NoAction is true (require the previous creations to occur)
is($mc->symlink($target_file2, $filelink), SUCCESS, "file symlink already exists: nothing done");
check_symlink($mc, $target_file2, $filelink, SUCCESS);
is($mc->symlink($target_file1, $filelink), CHANGED, "file symlink updated");
check_symlink($mc, $target_file1, $filelink, CHANGED);
# Check that the file to be redefined as a symlink really exists
ok(! readlink($target_file2), "$target_file2 exists and is a file");
my $link_status = $mc->symlink($target_file1, $target_file2);
ok(! defined($link_status), "symlink failed: existing file not replaced by a symlink");
is($mc->{fail},
   "*** cannot symlink $target_file2: it is not an existing symlink",
   "fail attribute set after symlink failure (existing file not replaced by a symlink)");
ok($mc->file_exists($target_file2) && ! $mc->is_symlink($target_file2), "File $target_file2 has not be replaced by a symlink");
$opts{force} = 1;
$CAF::Object::NoAction = 1;
is($mc->symlink($target_file1, $target_file2, %opts), CHANGED, "existing file would be replaced by a symlink (force option and NoAction set)");
ok($mc->file_exists($target_file2), "File $target_file2 not replaced by a symlink with 'force' option (NoAction set)");
$CAF::Object::NoAction = 0;
is($mc->symlink($target_file1, $target_file2, %opts), CHANGED, "existing file replaced by a symlink (force option set)");
check_symlink($mc, $target_file1, $target_file2, CHANGED);

# Invalid symlink updates
my $test_directory = "$basetest/$target_directory";
$link_status = $mc->symlink($target_file1, "$test_directory", %opts);
ok (! defined($link_status), "directory not replaced by a symlink (force option set)");
is($mc->{fail},
   "*** cannot symlink $test_directory: it is not an existing symlink",
   "fail attribute set after symlink failure (existing directory not replaced by a symlink)");
ok($mc->directory_exists($test_directory) && ! $mc->is_symlink($test_directory),
   "Directory $test_directory has not be replaced by a symlink");

# Broken symlinks with and without 'check' option
$opts{check} = 1;
ok(! $mc->symlink("really_really_missing", $brokenlink, %opts), "broken symlink not created (target existence enforced)");
ok(! -e $brokenlink && ! -l $brokenlink, "Broken link has not been created");
$opts{check} = 0;
is($mc->symlink("really_missing", $brokenlink), CHANGED, "broken symlink created");
ok($mc->is_symlink($brokenlink), "Broken link has been created (target check disabled by check=0)");
is(readlink($brokenlink), "really_missing", "Broken link has the expected target by check=0");
delete $opts{check};
is($mc->symlink("really_really_missing", $brokenlink), CHANGED, "broken symlink updated");
ok($mc->is_symlink($brokenlink), "Broken link has been updated (target check disabled by 'check' undefined)");
is(readlink($brokenlink), "really_really_missing", "Broken link has the expected target by 'check' undefined");

# noreset=0
diag ("symlink() calls: $symlink_call_count, _function_catch() calls: $function_catch_call_count");
verify_exception("symlink tests", "Failed to create symlink", $symlink_call_count + $function_catch_call_count, 0);
ok($mc->_reset_exception_fail(), "_reset_exception_fail after symlink tests");


# Test xxx_exists, is_hardlink and has_hardlinks methods with symlinks
# Needs symlinks created in previous step (symlink creation/update)

init_exception("existence tests (symlinks and hardlinks)");
my $hardlink = "$basetest/a_hardlink";

ok(! $mc->directory_exists($brokenlink), "directory_exists false on brokenlink");
ok(! $mc->file_exists($brokenlink), "file_exists false on brokenlink");
ok($mc->any_exists($brokenlink), "any_exists true on brokenlink");
ok($mc->is_symlink($brokenlink), "is_symlink true on brokenlink");
is($mc->hardlink($brokenlink, $hardlink), CHANGED, "hardlink created on broken link");
ok($mc->has_hardlinks($brokenlink), "broken link is a hard link");
is($mc->is_hardlink($brokenlink, $hardlink), 1, "$brokenlink and $hardlink are hard linked");

ok($mc->directory_exists($dirlink), "directory_exists true on dirlink");
ok(! $mc->file_exists($dirlink), "file_exists false on dirlink");
ok($mc->any_exists($dirlink), "any_exists true on dirlink");
ok($mc->is_symlink($dirlink), "is_symlink true on dirlink");
is($mc->hardlink($dirlink, $hardlink), CHANGED, "hardlink created on directory link");
ok($mc->has_hardlinks($dirlink), "directory link is a hard link");
is($mc->is_hardlink($dirlink, $hardlink), 1, "$dirlink and $hardlink are hard linked");

ok(! $mc->directory_exists($filelink), "directory_exists false on filelink");
ok($mc->file_exists($filelink), "file_exists true on filelink");
ok($mc->any_exists($filelink), "any_exists true on filelink");
ok($mc->is_symlink($filelink), "is_symlink true on filelink");
is($mc->hardlink($filelink, $hardlink), CHANGED, "hardlink created on file link");
ok($mc->has_hardlinks($filelink), "file link is a hard link");
is($mc->is_hardlink($filelink, $hardlink), 1, "$filelink and $hardlink are hard linked");

is(! $mc->is_hardlink($filelink, $dirlink), 1, "$filelink and $dirlink are not hard linked (different hard links)");

# noreset=0
verify_exception("existence tests (symlinks and hardlinks)", undef, 6, 0);
ok($mc->_reset_exception_fail(), "_reset_exception_fail after existence tests (symlinks and hardlinks)");


# Test hardlink creation

# Function to do the hardlink checks, taking into account NoAction flag
# This function also acts a unit test for has_hardlinks() and is_hardlink() methods
sub check_hardlink {
    my ($mc, $target, $link_path, $expected_status) = @_;
    my $noaction = $mc->_get_noaction();

    my $ok_msg;
    if ( $noaction ) {
        $ok_msg = "$link_path hardlink not created (NoAction set)";
    } else {
        $ok_msg = "$link_path is " . ($expected_status == CHANGED ? "" : "already ") . "a hardlink";
    }
    my $target_msg = "$link_path hardlink has the expected " . ($expected_status == CHANGED ? "changed " : "") . "target ($target)";

    # Test if symlink was created or not according to NoAction flag
    my $ok_condition;
    if ( $noaction ) {
        $ok_condition = ! $mc->any_exists($link_path);
    } else {
        $ok_condition = $mc->has_hardlinks($link_path);
    }
    ok($ok_condition, $ok_msg);

    ok($mc->is_hardlink($link_path, $target), $target_msg) unless $noaction;
};

init_exception("hardlink tests");

rmtree ($basetest) if -d $basetest;
my $cwd = cwd();
my $hardlink1 = "$basetest/$target_directory/hardlink1";
my $hardlink2 = "$basetest/$target_directory/hardlink2";
# hardlink target must be an absolute path or the link path directory is prepended
$target_file1 = "$cwd/$basetest/tgtfile1";
my $relative_target_file3 = "$basetest/$target_directory/tgtfile3";
my $target_file3 = "$cwd/$relative_target_file3";
writefile($target_file1);
writefile($target_file3);

for $CAF::Object::NoAction (1,0) {
    is($mc->hardlink($target_file1, $hardlink1), CHANGED, "hardlink created");
    check_hardlink($mc, $target_file1, $hardlink1, CHANGED);
    if ( !$CAF::Object::NoAction ) {
        is($mc->hardlink($target_file1, $hardlink1), SUCCESS, "hardlink already exists");
        check_hardlink($mc, $target_file1, $hardlink1, SUCCESS);
    }
    is($mc->hardlink($target_file3, $hardlink1), CHANGED, "hardlink updated");
    check_hardlink($mc, $target_file3, $hardlink1, CHANGED);
    is($mc->hardlink($relative_target_file3, $hardlink2), CHANGED, "relative hardlink created");
    check_hardlink($mc, $target_file3, $hardlink2, CHANGED);
}

# The following tests are not affected by NoAction flag
$link_status = $mc->hardlink("missing_file", $hardlink1);
ok(! $link_status, "hardlink not created (target has to exist)");
is($mc->{fail},
   "*** invalid target (missing_file): lstat(missing_file): No such file or directory",
   "fail attribute set after hardlink error");
$link_status = $mc->hardlink($target_file1, "$basetest/$target_directory");
ok(! $link_status, "hardlink not created (do not replace an existing directory)");
is($mc->{fail},
   "*** cannot hard link $basetest/$target_directory: it is a directory",
   "fail attribute set after hardlink error (existing directory not replaced)");
is($mc->hardlink($target_file1, $hardlink2), CHANGED, "hardlink2 created");
is($mc->is_hardlink($hardlink1, $hardlink2), 0, "is_hardlink false (0) with 2 different hardlinks");

# noreset=0
diag ("hardlink() calls: $hardlink_call_count, _function_catch() calls: $function_catch_call_count");
verify_exception("hardlink tests", "\\*\\*\\* invalid target", $hardlink_call_count + $function_catch_call_count, 0);
ok($mc->_reset_exception_fail(), "_reset_exception_fail after hardlink tests");


=head2 directory

=cut

rmtree ($basetest) if -d $basetest;
$mc->{fail} = undef;
ok(! defined $mc->directory("\0"), "failing untaint directory returns undef");
is($mc->{fail}, "Failed to untaint directory: path \0",
   "fail attribute set for failing directory untaint");

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

$mc->{fail} = undef;
ok(! defined $mc->cleanup("\0"), "failing untaint cleanup returns undef");
is($mc->{fail}, "Failed to untaint cleanup dest: path \0",
   "fail attribute set for failing cleanup dest untaint");

# Tests without NoAction
$CAF::Object::NoAction = 0;

# test with dir and file, without backup
my $cleanupdir1 = "$basetest/cleanup1";
my $cleanupfile1 = "$cleanupdir1/file";
my $cleanupfile1b = "$cleanupfile1.old";

rmtree($cleanupdir1) if -d $cleanupdir1;
writefile($cleanupfile1);
ok($mc->file_exists($cleanupfile1), "cleanup testfile exists");
ok($mc->directory_exists($cleanupdir1), "cleanup testdir exists");

is($mc->cleanup($cleanupfile1, ''), CHANGED,"cleanup testfile, no backup ok");
ok(! $mc->file_exists($cleanupfile1), "cleanup testfile does not exist anymore");

is($mc->cleanup($cleanupdir1, ''), CHANGED, "cleanup testdir, no backup ok");
ok(! $mc->directory_exists($cleanupdir1), "cleanup testdir does not exist anymore");

# test with dir and file, without backup
rmtree($cleanupdir1) if -d $cleanupdir1;
writefile($cleanupfile1);
is(readfile($cleanupfile1), 'ok', 'cleanupfile has expected content');
writefile("$cleanupfile1b", "woohoo");
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
writefile($cleanupfile1);

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
writefile($basetestfile);

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
writefile($basetestfile);

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
writefile($basetestfile);


$tempdir = "$basetest/sub/exist-X";

my $basetempdir = dirname($tempdir);
# use this to create the subdir
ok($mc->directory($tempdir), "Testdir template exists");
ok($mc->directory_exists($basetempdir), "Testdir basedir exists");

# remove all permissions on basedir
chmod(0000, $basetempdir);

init_exception("temp directory creation failure NoAction=0 permission");

ok(!defined($mc->directory($tempdir, temp => 1)),
   "temp directory on parent without permissions returns undef on failure tempdir");

# called 2 times: init and _safe_eval
verify_exception("temp directory creation failure NoAction=0 permission",
                 '^Failed to create temporary directory target/test/check/sub/exist-XXXXX: Error in tempdir\(\) using target/test/check/sub/exist-XXXXX: Could not create directory target/test/check/sub/exist-\w{5}: Permission denied at', 2);

# reset write bits for removal
chmod(0700, $basetempdir);

# reenable NoAction
$CAF::Object::NoAction = 1;

=head2 status missing file

=cut

$mc->{fail} = undef;
ok(! defined $mc->status("\0"), "failing untaint status returns undef");
is($mc->{fail}, "Failed to untaint status: path \0",
   "fail attribute set for failing status untaint");


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

writefile($statusfile);
ok($mc->file_exists($statusfile), "status testfile exists");
chmod(0755, $statusfile);
# Stat returns type and permissions
$mode = (stat($statusfile))[2] & 07777;
is($mode, 0755, "created statusfile has mode 0755");


# enable NoAction
$CAF::Object::NoAction = 1;

rmtree($basetest) if -d $basetest;

writefile($statusfile);
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

writefile($statusfile);
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

=head2 move

=cut


$mc->{fail} = undef;
ok(! defined $mc->move("\0", "ok"), "failing untaint move src returns undef");
is($mc->{fail}, "Failed to untaint move src: path \0",
   "fail attribute set for failing move src untaint");

$mc->{fail} = undef;
ok(! defined $mc->move("ok", "\0"), "failing untaint move dest returns undef");
is($mc->{fail}, "Failed to untaint move dest: path \0",
   "fail attribute set for failing move dest untaint");

# disable NoAction
$CAF::Object::NoAction = 0;

# make dest with content
# make dest backup with content
# move src to dest
# test with dir and file, without backup
my $movedir1 = "$basetest/move1";
my $movedir2 = "$basetest/move2";
my $movesrc1 = "$movedir1/src";
my $movedest1 = "$movedir2/dst";
my $movedest1b = "$movedest1.old";

rmtree($movedir1) if -d $movedir1;
rmtree($movedir2) if -d $movedir2;
writefile($movesrc1, 'source');
writefile($movedest1, 'dest');
writefile($movedest1b, 'dest backup');
ok($mc->file_exists($movesrc1), "move src file exists");
ok($mc->file_exists($movedest1), "move dest file exists");
ok($mc->file_exists($movedest1b), "move dest backup file exists");
ok($mc->directory_exists($movedir1), "move testdir exists");
my $nrfiles = scalar grep {-f $_} glob("$movedir2/*");
is($nrfiles, 2, "$nrfiles files in dest dir before move");

init_exception("move NoAction=0");
is($mc->move($movesrc1, $movedest1, '.old'), CHANGED, "move src $movesrc1 to dest $movedest1 with backup '.old'");
# 4 calls,
#   one from init move
#   two from hardlink from backup (init hardlink and function_catch)
#   one from safe_eval FCmove
verify_exception("move NoAction=0", undef, 4);

ok(! $mc->file_exists($movesrc1), "move src file does not exists, was moved");
ok($mc->file_exists($movedest1), "move dest file exists after move");
is(readfile($movedest1), 'source', 'dest file has source content');
ok($mc->file_exists($movedest1b), "move dest backup file exists after move");
is(readfile($movedest1b), 'dest', 'dest backup file has (original) dest content after move');
# test that e.g. no .old.old exists/is created
$nrfiles = scalar grep {-f $_} glob("$movedir2/*");
is($nrfiles, 2, "$nrfiles files in dest dir after move");

# same, but w/o backup

rmtree($movedir1) if -d $movedir1;
rmtree($movedir2) if -d $movedir2;
writefile($movesrc1, 'source');
writefile($movedest1, 'dest');
writefile($movedest1b, 'dest backup');
ok($mc->file_exists($movesrc1), "move src file exists w/o backup");
ok($mc->file_exists($movedest1), "move dest file exists w/o backup");
ok($mc->file_exists($movedest1b), "move dest backup file exists w/o backup");
ok($mc->directory_exists($movedir1), "move testdir exists w/o backup");
$nrfiles = scalar grep {-f $_} glob("$movedir2/*");
is($nrfiles, 2, "$nrfiles files in dest dir before move w/o backup");

init_exception("move w/o backup NoAction=0");
is($mc->move($movesrc1, $movedest1, ''), CHANGED, "move src $movesrc1 to dest $movedest1 w/o backup");
verify_exception("move w/o backup NoAction=0", undef, 2); # move init, safe eval FCmove
ok(! $mc->file_exists($movesrc1), "move src file does not exists, was moved w/o backup");
ok($mc->file_exists($movedest1), "move dest file exists after move w/o backup");
is(readfile($movedest1), 'source', 'dest file has source content w/o backup');
ok($mc->file_exists($movedest1b), "move dest backup file exists after move w/o backup");
is(readfile($movedest1b), 'dest backup', 'dest backup file has (original) dest backup content after move w/o backup');
# test that e.g. no .old.old exists/is created
$nrfiles = scalar grep {-f $_} glob("$movedir2/*");
is($nrfiles, 2, "$nrfiles files in dest dir after move w/o backup");

# same, but w/o backup, and destdir does not exists
rmtree($movedir1) if -d $movedir1;
rmtree($movedir2) if -d $movedir2;
writefile($movesrc1, 'source');
ok($mc->file_exists($movesrc1), "move src file exists w/o backup w/o destdir");
ok(!$mc->file_exists($movedest1), "move dest file does not exist w/o backup w/o destdir");
ok(!$mc->file_exists($movedest1b), "move dest backup file does not exists w/o backup w/o destdir");
ok($mc->directory_exists($movedir1), "move testdir exists w/o backup w/o destdir");
ok(!$mc->directory_exists($movedir2), "move dest testdir does not exists w/o backup w/o destdir");

init_exception("move w/o backup  w/o destdir NoAction=0");
is($mc->move($movesrc1, $movedest1, ''), CHANGED, "move src $movesrc1 to dest $movedest1 w/o backup w/o destdir");
# move,
#  directory + func_catch + status/LC_Chekc/func_catch
#  safe eval FCmove
verify_exception("move w/o backup w/o destdir NoAction=0", undef, 5);
ok(! $mc->file_exists($movesrc1), "move src file does not exists, was moved w/o backup w/o destdir");
ok($mc->directory_exists($movedir2), "move dest testdir does exists after move w/o backup w/o destdir");
ok($mc->file_exists($movedest1), "move dest file exists after move w/o backup w/o destdir");
is(readfile($movedest1), 'source', 'dest file has source content w/o backup w/o destdir');
ok(!$mc->file_exists($movedest1b), "move dest backup file does not exists after move w/o backup w/o destdir");
# test that e.g. no .old.old exists/is created
$nrfiles = scalar grep {-f $_} glob("$movedir2/*");
is($nrfiles, 1, "$nrfiles files in dest dir after move w/o backup w/o destdir");

# move failures
# trigger failure
#   subbir on broken symlink, cannot make parent dir of dest
rmtree($movedir1) if -d $movedir1;
writefile($movesrc1, 'source');

my $movedest2 = "$brokenlink/sub/dst";
ok(symlink("really_really_missing", $brokenlink), "broken symlink created 1");

# no backup, there's no dest to backup anyway
init_exception("move failure to create destdir");
ok(! defined($mc->move($movesrc1, $movedest2, '')),
   "move src $movesrc1 to dest $movedest1 w/o backup failed no permission to create destdir");
verify_exception("move failure to create destdir",
                 '^Failed to create basedir for dest target/test/check/broken_symlink/sub/dst: \*\*\* mkdir\(target/test/check/broken_symlink, 0755\): File exists', 3);

# make destdir and remove all permissions
mkpath $movedir2;
chmod(0000, $movedir2);
# no backup, there's no dest to backup anyway
init_exception("move failure to move source");
ok(! defined($mc->move($movesrc1, $movedest1, '')),
   "move src $movesrc1 to dest $movedest1 w/o backup failed no permission to move src to dest (destdor exists)");
verify_exception("move failure to move source",
                 '^Failed to move target/test/check/move1/src to target/test/check/move2/dst: Permission denied', 2);

chmod(0700, $movedir2);
writefile($movedest1, 'dest');

# do not set 0000, or else Path cannot detect that dest exists
# and thus no backup is taken, and we get different failure
chmod(0500, $movedir2);
init_exception("move failure to cleanup dest with backup");
ok(! defined($mc->move($movesrc1, $movedest1, '.old')),
   "move src $movesrc1 to dest $movedest1 with backup '.old' failed no permission to make backup of dest");
verify_exception("move failure to cleanup dest with backup",
                 '^move: backup of dest target/test/check/move2/dst to target/test/check/move2/dst.old failed: \*\*\* link\(target/test/check/move2/dst, target/test/check/move2/dst.old\): Permission denied', 3);

# Restore sufficient permissions
chmod(0700, $movedir2);

# NoAction, same test

# enable NoAction
$CAF::Object::NoAction = 1;

rmtree($movedir1) if -d $movedir1;
rmtree($movedir2) if -d $movedir2;
writefile($movesrc1, 'source');
writefile($movedest1, 'dest');
writefile($movedest1b, 'dest backup');
ok($mc->file_exists($movesrc1), "move src file exists NoAction=1");
ok($mc->file_exists($movedest1), "move dest file exists NoAction=1");
ok($mc->file_exists($movedest1b), "move dest backup file exists NoAction=1");
ok($mc->directory_exists($movedir1), "move testdir exists NoAction=1");
$nrfiles = scalar grep {-f $_} glob("$movedir2/*");
is($nrfiles, 2, "$nrfiles files in dest dir before move NoAction=1");

is($mc->move($movesrc1, $movedest1, '.old'), CHANGED, "move src $movesrc1 to dest $movedest1 with backup '.old' NoAction=1");
ok($mc->file_exists($movesrc1), "move src file still exists after move NoAction=1");
is(readfile($movesrc1), 'source', 'src file has source content NoAction=1');
ok($mc->file_exists($movedest1), "move dest file still exists after move NoAction=1");
is(readfile($movedest1), 'dest', 'dest file has dest content NoAction=1');
ok($mc->file_exists($movedest1b), "move dest backup file exists after move NoAction=1");
is(readfile($movedest1b), 'dest backup', 'dest backup file has dest backup content after move NoAction=1');
$nrfiles = scalar grep {-f $_} glob("$movedir2/*");
is($nrfiles, 2, "$nrfiles files in dest dir after move NoAction=1");

# reenable NoAction
$CAF::Object::NoAction = 1;

done_testing();
