use strict;
use warnings;

use FindBin qw($Bin);
use lib "$Bin/modules";

use CAF::FileEditor;

use Test::More tests => 10;
use Test::MockModule;
use Test::Quattor::Object;
use Carp qw(confess);
use File::Path;
use File::Temp qw(tempfile);
use Readonly;

$SIG{__DIE__} = \&confess;

# FIXME:
# LC::File::file_contents (used by CAF::FileEditor constructor) doesn't work
# in the unit test context. Mock it until we find a better solution...
our $lcfile = Test::MockModule->new("LC::File");

sub read_file_contents {
    my $fname = shift;
    my $fh;
    open($fh, "<", $fname) || die ("failed to open $fname");
    my $contents = join('', <$fh>);
    return $contents;
}
$lcfile->mock("file_contents", \&read_file_contents);


my $testdir = 'target/test/fileeditor_source';
mkpath($testdir);
(undef, my $filename) = tempfile(DIR => $testdir);

Readonly my $TEXT => <<EOF;
En un lugar de La Mancha, de cuyo nombre no quiero acordarme
no ha tiempo que vivía un hidalgo de los de lanza en astillero...
EOF
Readonly my $ANOTHER_TEXT => "adarga antigua, rocín flaco y galgo corredor.";

my $fh;
my $obj = Test::Quattor::Object->new();


# Create a file and check that it is empty
($fh, $filename) = tempfile(DIR => $testdir);
$fh->close();
$fh = CAF::FileEditor->new($filename, log => $obj);
is("$fh", "", "Existing file ($filename) empty");
ok(!$fh->close(), "No changes to empty file");

# Check that reference file contents is used as the initial contents when it
# is newer than the file edited.
my $time = time();
utime($time, $time - 10, $filename); # make filename old enough
my ($ref_fh, $ref_filename) = tempfile(DIR => $testdir);
print $ref_fh $TEXT;
$ref_fh->close();

$fh = CAF::FileEditor->new($filename, log => $obj, source => $ref_filename);
is(*$fh->{options}->{source}, $ref_filename, "File source is correctly defined");
ok($fh->_is_reference_newer(), "Source file ($ref_filename) is newer than actual file ($filename)");
is("$fh", $TEXT, "Reference file ($filename) contents used");
ok($fh->close(), "change on close (nothing was printed to filehandle, but source is different from original file)");

# Check that reference file contents is not used as the initial contents when it
# is older than the file edited.
$time = time();
utime($time, $time - 10, $ref_filename); # make ref_filename old enough
my ($new_fh, $new_filename) = tempfile(DIR => $testdir);
print $new_fh $ANOTHER_TEXT;
$new_fh->close();

$new_fh = CAF::FileEditor->new($new_filename, log => $obj, source => $ref_filename);
is(*$new_fh->{options}->{source}, $ref_filename, "File source is correctly defined");
ok(!$new_fh->_is_reference_newer(), "Source file ($ref_filename) is older than actual file ($filename)");
is("$new_fh", $ANOTHER_TEXT, "Existing file ($new_filename) contents used");
ok(!$fh->close(), "no change on close (source is too old)");

done_testing();
