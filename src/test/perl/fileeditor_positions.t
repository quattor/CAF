#!/usr/bin/perl
use strict;
use warnings;
use FindBin qw($Bin);
use lib "$Bin/modules";
use testapp;
use CAF::FileEditor;
use Test::More;
use Test::Quattor::Object;
use Carp qw(confess);
use Fcntl qw(:seek);

use File::Path;
use File::Temp qw(tempfile);

my $testdir = 'target/test/editor';
mkpath($testdir);
(undef, our $filename) = tempfile(DIR => $testdir);

chomp($filename);

my ($log, $str);
my $this_app = testapp->new ($0, qw (--verbose));

$SIG{__DIE__} = \&confess;

open ($log, ">", \$str);
use constant TEXT => <<'EOF';
# we goan em zn broek afdoen
# tsjoelala tsjoelala
we goan hem zn broek afdoen
tsjoe
la
la
EOF

my $fh = CAF::FileEditor->new ($filename);
$fh->set_contents(TEXT);

# get positions of line starting with 'we goan'
# 1st line has 29 characters (incl newline), 2nd 22, 3rd 28
my $startof3rdline = 29+22; # before 3rd line = after the newline of 2nd line
my $after3rdline =29+22+28; # after the newline of 3rd line

# default whence/offset: start from beginning
my ($before,$after) = $fh->get_all_positions(qr{^we goan.*$}m);
is(scalar @$before, scalar @$after, 'Before and after matches are equal');
is(scalar @$before, 1, 'Only one match expected');
is(scalar @$after, 1, 'Only one match expected');
is($before->[0], $startof3rdline, 'Found before position'); 
is($after->[0], $after3rdline, 'Found after position'); 

$fh->seek($after3rdline, SEEK_SET);

# shouldn't match anymore
my ($before2, $after2) = $fh->get_all_positions(qr{^we goan.*$}m, SEEK_CUR);

is($fh->pos, $after3rdline, 'Current position restored');
is(scalar @$before2, 0, 'No before position found');
is(scalar @$after2, 0, 'No after position found');


my ($start,$end) = $fh->get_header_positions();
is($start, 0, 'start of headers');
is($end, $startof3rdline, 'start of headers');

$fh->seek($startof3rdline, SEEK_SET);
($start,$end) = $fh->get_header_positions(undef, SEEK_CUR);
# restore position
is($fh->pos, $startof3rdline, 'Current position restored');
is($start, -1, 'No start of headers');
is($end, -1, 'No start of headers');


$fh->cancel();


done_testing();
