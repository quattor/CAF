#!/usr/bin/perl

BEGIN {
    unshift (@INC, qw (. .. ../../perl-LC));
}

use strict;
use warnings;
use testapp;
use CAF::FileEditor;
use Test::More tests => 6;
use constant FILENAME => '/my/path';
use constant TEXT => <<EOF;
En un lugar de La Mancha, de cuyo nombre no quiero acordarme
no ha mucho tiempo vivía un hidalgo de los de adarga antigua...
EOF

our $text = TEXT;

our %opts = ();
our $path;
my ($log, $str);
my $this_app = testapp->new ($0, qw (--verbose));

open ($log, ">", \$str);
my $fh = CAF::FileEditor->new (FILENAME);
isa_ok ($fh, "CAF::FileEditor", "Correct class after new method");
isa_ok ($fh, "CAF::FileWriter", "Correct class inheritance after new method");
is (${$fh->string_ref()}, TEXT, "File opened and correctly read");
$fh->close();

is ($opts{contents}, TEXT, "Attempted to write the file with the correct contents");
$fh = CAF::FileEditor->open (FILENAME);
isa_ok ($fh, "CAF::FileEditor", "Correct class after open method");
isa_ok ($fh, "CAF::FileWriter", "Correct class inheritance after open method");
