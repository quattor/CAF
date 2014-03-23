#!/usr/bin/perl
use strict;
use warnings;
use FindBin qw($Bin);
use lib "$Bin/", "$Bin/..", "$Bin/../../perl-LC";
use testapp;
use CAF::FileEditor;
use Test::More;
use Carp qw(confess);
use Fcntl qw(:seek);

my $filename = `mktemp`;

chomp($filename);

my ($log, $str);
my $this_app = testapp->new ($0, qw (--verbose));

$SIG{__DIE__} = \&confess;

*testapp::error = sub {
    my $self = shift;
    $self->{ERROR} = @_;
};

open ($log, ">", \$str);
my $fh = CAF::FileEditor->new ($filename);

# begin/end tests for humans
$fh->add_or_replace_lines(qr/xxx/, qr/yyy/, 'END1', ENDING_OF_FILE);
like("$fh", qr/END1$/, 'Initial ending using predefined constants');

$fh->add_or_replace_lines(qr/xxx/, qr/yyy/, 'BEGIN1', BEGINNING_OF_FILE);
like("$fh", qr/^BEGIN1/, 'Initial beginning using predefined constants');

is("$fh", "BEGIN1END1", "Begin and end added");

# expert mode
$fh->add_or_replace_lines(qr/xxx/, qr/yyy/, 'begin2', SEEK_SET);
like("$fh", qr/^begin2BEGIN1/, 'Add to begin using whence SET (default offset)');

$fh->add_or_replace_lines(qr/xxx/, qr/yyy/, 'end2', SEEK_END);
like("$fh", qr/END1end2$/, 'Add to end using whence END (default offset)');

is("$fh", "begin2BEGIN1END1end2", "Begin and end added part 2");

# go to pos 5
$fh->add_or_replace_lines(qr/xxx/, qr/yyy/, 'Begin3', SEEK_SET, 5);
like("$fh", qr/^beginBegin3/, 'Add to begin using whence SET with offset');

is("$fh", "beginBegin32BEGIN1END1end2", "Begin and end added part 3");

# ok, let the bizare stuff begin
# go to position 5 from the beginning
$fh->seek(5, SEEK_SET);
# add to the current position with an extra offset of 5
$fh->add_or_replace_lines(qr/xxx/, qr/yyy/, 'bEgIn4', SEEK_CUR, 5);
like("$fh", qr/^beginBeginbEgIn4/, 'CUR whence with offset 5 (after seek 5)');

is("$fh", "beginBeginbEgIn432BEGIN1END1end2", "Begin and end added part 4");

# offset with SEEK_END
my $origlength=length "$fh";
$fh->seek(3, SEEK_END);
is(length "$fh", $origlength + 3, "Seek beyond end should pad");
like("$fh", qr/END1end2\0\0\0$/, 'Seek beyond end should pad (text match)');

$fh->add_or_replace_lines(qr/xxx/, qr/yyy/, 'End3', SEEK_END);
$fh->add_or_replace_lines(qr/xxx/, qr/yyy/, 'eNd4', SEEK_END, 3);
like("$fh", qr/End3\0\0\0eNd4$/, 'Add to end using whence END with offset part 3 and 4');


$fh->cancel();

use constant TEXT => <<'EOF';
# we goan em zn broek afdoen
# tsjoelala tsjoelala
we goan hem zn broek afdoen
tsjoe
la
la
EOF

$fh = CAF::FileEditor->new ($filename);
$fh->set_contents(TEXT);
my $tt="$fh";
my $ltt=length $tt;
diag("$ltt $tt");

my ($start,$end) = $fh->get_header_positions();
$fh->add_or_replace_lines(qr/xxx/, qr/yyy/, "tsjoelala\n", SEEK_SET, $end);
like("$fh", qr/# tsjoelala tsjoelala\ntsjoelala\nwe goan hem/, 'Insert text after header');

my ($before, $after) = $fh->get_all_positions('^tsjoelala.*$');
# ok, $after (and $before) is a reference to an array; 
# if you pass it instead of eg $after->[0], you pass a very big number,
# creating a very big string
$fh->add_or_replace_lines(qr/xxx/, qr/yyy/, "tsjoelala\n", SEEK_SET, $after->[0]);
like("$fh", qr/# tsjoelala tsjoelala\ntsjoelala\ntsjoelala\nwe goan hem/, 'Insert text after matching line');

$fh->cancel();


done_testing();
