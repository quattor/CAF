#!/usr/bin/perl

BEGIN {
    unshift (@INC, qw (. .. ../../perl-LC));
}

use strict;
use warnings;
use testapp;
use CAF::FileEditor;
use Test::More tests => 7;
use constant FILENAME => '/my/path';
use constant TEXT => <<EOF;
En un lugar de La Mancha, de cuyo nombre no quiero acordarme
no há mucho tiempo que vivía un hidalgo de los de lanza en astillero...
EOF
use constant HEADTEXT => <<EOF;
... adarga antigua, rocín flaco y galgo corredor.
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
$fh->head_print (HEADTEXT);
is (${$fh->string_ref()}, HEADTEXT . TEXT,
    "head_print method working properly");
isa_ok ($fh, "CAF::FileEditor", "Correct class after open method");
isa_ok ($fh, "CAF::FileWriter", "Correct class inheritance after open method");
