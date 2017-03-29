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
my $mode = (stat($fn))[2] & 07777;
is($mode, 0764, "created file $fn has mode 0764");
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
