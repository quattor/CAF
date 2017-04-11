use strict;
use warnings;

BEGIN {
    # remove the module path that is holding the temp LC mock
    # we actually want to run something here
    @INC = grep { $_ !~ m/resources$/ } @INC;
}

use Test::More;
$SIG{__WARN__} = sub {ok(0, "Perl warning: $_[0]");};

use FindBin qw($Bin);
use lib "$Bin/modules";
use testapp;
use Test::Quattor::Filetools qw(writefile readfile);;

use File::Path qw(mkpath);
use File::Temp qw(tempfile);

use CAF::FileWriter;

use Test::Quattor::Object;
my $obj = Test::Quattor::Object->new();

use LC::Exception;
my $EC = LC::Exception::Context->new()->will_store_errors();

use Readonly;

Readonly my $TEXT => "test\n";

sub get_perm {(stat($_[0]))[2] & 07777;};

my ($fn, $fh);

my $testdir = 'target/test/writer-notmocked';
mkpath($testdir);
(undef, my $filename) = tempfile(DIR => $testdir);

$fn = "$testdir/noaction";

# success NoAction
$CAF::Object::NoAction = 1;

ok(! -f $fn, "file $fn does not exist noaction=1");

$fh = CAF::FileWriter->open ($fn, mtime => 1234567, mode => 0764, log => $obj);
print $fh $TEXT;
is ("$fh", $TEXT, "Stringify works noaction=1");
$fh->close();

ok(! -f $fn, "file $fn does not exist after noaction=1");

# test success
$CAF::Object::NoAction = 0;
$fn = "$testdir/success/file";

# to test creation of parentdir
ok(! -d "$testdir/success", "basedir of file $fn does not exist");
$fh = CAF::FileWriter->open ($fn, mtime => 1234567, mode => 0764, log => $obj);
print $fh $TEXT;
is ("$fh", $TEXT, "Stringify works in noaction=0");
$fh->close();

is_deeply($obj->{LOGLATEST}->{EVENT}, {
    '_objref' => 'CAF::FileWriter',
    'backup' => undef,
    'changed' => 1,
    'diff' => $TEXT,
    'filename' => 'target/test/writer-notmocked/success/file',
    'modified' => 1,
    'noaction' => 0,
    'save' => 1
}, "event on close");

# test content
is(readfile($fn), $TEXT, "file $fn created with expected contents");
# stat test mtime, mode
is(get_perm($fn), 0764, "created file $fn has mode 0764");
is((stat($fn))[9], 1234567, "mtime set to 1234567 forfile $fn");

# test with existing file
$fn = "$testdir/success/file2";
writefile($fn, "garbage");
$fh = CAF::FileWriter->open ($fn, log => $obj);
print $fh $TEXT;
$fh->close();

# test content
is(readfile($fn), $TEXT, "file $fn created with expected contents with previous existing file");
like($obj->{LOGLATEST}->{EVENT}->{diff},
     qr{@@ -1 \+1 @@\n-garbage(\n\\ No newline at end of file\n)?\+test\n},
     "event diff on close");

# verify LC::Check behaviour
# if we ever get rid of LC, the LC part of the test can be removed

# force mask
#   so do not use mkpath from File::Path as AtomicWrite does
# For now, test with ncm-ncd mask
# TODO: test restrictive mask (see CAF #242)
my $oldmask = umask 022;

my $defdirperm = 0755;
my $deffileperm = 0644;

my $pdir = "$testdir/success_lc";
ok(! -d $pdir, "parent dir $pdir doesn't exist for LC");
my $pdir2 = "$pdir/level2";
ok(! -d $pdir2, "2nd level parent dir $pdir2 doesn't exist for LC");
$fn = "$pdir2/file1";
use LC::Check;
LC::Check::file($fn, contents=>"a");
# check permisssions on file and subdir
is(get_perm($fn), $deffileperm, "LC created file $fn has default mode 0644");
is(get_perm($pdir), $defdirperm, "LC created parentdir $pdir has default mode 0755");
is(get_perm($pdir2), $defdirperm, "LC created 2nd level parentdir $pdir has default mode 0755");


$pdir = "$testdir/success_fw";
ok(! -d $pdir, "parent dir $pdir doesn't exist");
$pdir2 = "$pdir/level2";
ok(! -d $pdir2, "2nd level parent dir $pdir2 doesn't exist");
$fn = "$pdir2/file1";
$fh = CAF::FileWriter->open ($fn, log => $obj);
print $fh $TEXT;
$fh->close();

# check permisssions on file and subdir
is(get_perm($fn), $deffileperm, "created file $fn has default mode 0644");
is(get_perm($pdir), $defdirperm, "created parentdir $pdir has default mode 0755");
is(get_perm($pdir2), $defdirperm, "created 2nd level parentdir $pdir has default mode 0755");

# restore mask
umask $oldmask;

# test failure
ok(! $EC->error(), "No previous error before failure check");

$testdir = "$testdir/fail";
mkpath($testdir);
# read+execute, but no write
# is needed, othwerise the _read_contents will fail, before AtomicWrite is used
chmod (0500, $testdir);
$fn = "$testdir/file";

$fh = CAF::FileWriter->open ($fn, log => $obj);
print $fh $TEXT;
is ("$fh", $TEXT, "Stringify works");
$fh->close();
ok($EC->error(), "old-style exception thrown");
like($EC->error->text, qr{^close AtomicWrite failed filename target/test/writer-notmocked/fail/file: Error in tempfile\(\) using (?:template )?target/test/writer-notmocked/fail/.tmp.XXXXXXXXXX: Could not create temp file target/test/writer-notmocked/fail/.tmp.\w+: Permission denied at },
     "message from die converted in exception");
$EC->ignore_error();



done_testing();
