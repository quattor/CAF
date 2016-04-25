#!/usr/bin/perl
use strict;
use warnings;
use FindBin qw($Bin);
use lib "$Bin/modules";
use CAF::FileEditor;
use Test::More tests => 3;
use Test::Quattor::Object;
use Carp qw(confess);
use File::Path;
use File::Temp qw(tempfile);

my $testdir = 'target/test/editor';
mkpath($testdir);
(undef, my $filename) = tempfile(DIR => $testdir);

use constant TEXT => <<EOF;
En un lugar de La Mancha, de cuyo nombre no quiero acordarme
no ha tiempo que vivía un hidalgo de los de lanza en astillero...
EOF

my $fh;
my $obj = Test::Quattor::Object->new();

$SIG{__DIE__} = \&confess;


# Create a file and check that it is empty
($fh, $filename) = tempfile(DIR => $testdir);
$fh->close();
$fh = CAF::FileEditor->new($filename, log => $obj);
is("$fh","","Existing file ($filename) empty");
$fh->close();

# Check that reference file contents is used as the initial contents when it
# is newer than the file edited.
sleep 2;
my ($ref_fh, $ref_filename) = tempfile(DIR => $testdir);
print $ref_fh TEXT;
$ref_fh->close();
$fh = CAF::FileEditor->new($filename, log => $obj, source => $ref_filename);
is("$fh",TEXT,"Reference file ($filename) contents used");
$fh->close();

# Check that reference file contents is not used as the initial contents when it
# is older than the file edited.
sleep 2;
my ($new_fh, $new_filename) = tempfile(DIR => $testdir);
$new_fh->close();
$new_fh = CAF::FileEditor->new($new_filename, log => $obj, source => $ref_filename);
is("$new_fh","","Existing file ($new_filename) contents used");
$fh->close();

done_testing();
