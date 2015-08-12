#!/usr/bin/perl
use strict;
use warnings;
use FindBin qw($Bin);
use lib "$Bin/", "$Bin/..", "$Bin/../../perl-LC";
use testapp;
use CAF::FileEditor;
use Test::Quattor::Object;
use Test::More;
use Carp qw(confess);
use Fcntl qw(:seek);

my $filename = `mktemp --tmpdir=target`;
chomp($filename);

my ($log, $str);
my $this_app = testapp->new ($0, qw (--verbose));
my $obj = Test::Quattor::Object->new();

$SIG{__DIE__} = \&confess;

*testapp::error = sub {
    my $self = shift;
    $self->{ERROR} = @_;
};

open ($log, ">", \$str);
my $fh = CAF::FileEditor->new ($filename, log => $obj);

# begin/end tests for humans
$fh->add_or_replace_lines(qr/xxx/, qr/yyy/, 'END1a', ENDING_OF_FILE);
like("$fh", qr/END1a$/, 'Initial ending using predefined constants');

$fh->add_or_replace_lines(qr/xxx/, qr/yyy/, 'BEGIN1', BEGINNING_OF_FILE);
like("$fh", qr/^BEGIN1/, 'Initial beginning using predefined constants');

# no newlines here because the BEGIN is inserted after the END is inserted
is("$fh", "BEGIN1END1a", "Begin and end added");

$fh->add_or_replace_lines(qr/xxx/, qr/yyy/, 'END1', ENDING_OF_FILE);
like("$fh", qr/END1a\nEND1$/, 'New ending using predefined constants, newline is inserted');
is("$fh", "BEGIN1END1a\nEND1", "Begin and 2 ends added");

$fh->add_or_replace_lines(qr/xxx/, qr/yyy/, "\nEND1b", ENDING_OF_FILE);
like("$fh", qr/END1a\nEND1\nEND1b$/,
     'insert text that starts with newline after line that does not end with newline, no extra newline is inserted');
is("$fh", "BEGIN1END1a\nEND1\nEND1b", "Begin and 3 ends added");

# expert mode
# inserting at begin of text requires no disabling of add_after_newline
$fh->add_or_replace_lines(qr/xxx/, qr/yyy/, 'begin2', SEEK_SET);
like("$fh", qr/^begin2BEGIN1/, 'Add to begin using whence SET (default offset)');

# disable add_after_newline
$fh->add_or_replace_lines(qr/xxx/, qr/yyy/, 'end2', SEEK_END, undef, 0);
like("$fh", qr/END1bend2$/, 'Add to end using whence END (default offset)');

is("$fh", "begin2BEGIN1END1a\nEND1\nEND1bend2", "Begin and end added part 2");

# go to pos 5
# disable add_after_newline
$fh->add_or_replace_lines(qr/xxx/, qr/yyy/, 'Begin3', SEEK_SET, 5, 0);
like("$fh", qr/^beginBegin3/, 'Add to begin using whence SET with offset');

is("$fh", "beginBegin32BEGIN1END1a\nEND1\nEND1bend2", "Begin and end added part 3 w/o add_after_newline");

# with add_after_newline enabled
$fh->add_or_replace_lines(qr/xxx/, qr/yyy/, 'Begin3b', SEEK_SET, 5);
like("$fh", qr/^begin\nBegin3b/, 'Add to begin using whence SET with offset with add_after_newline');

is("$fh", "begin\nBegin3bBegin32BEGIN1END1a\nEND1\nEND1bend2", "Begin and end added part 3");


# ok, let the bizare stuff begin
# go to position 6 from the beginning (after newline)
$fh->seek(6, SEEK_SET);
# add to the current position with an extra offset of 5
# disable add_after_newline
$fh->add_or_replace_lines(qr/xxx/, qr/yyy/, 'bEgIn4', SEEK_CUR, 5, 0);
like("$fh", qr/^begin\nBeginbEgIn4/, 'CUR whence with offset 5 (after seek 5)');

is("$fh", "begin\nBeginbEgIn43bBegin32BEGIN1END1a\nEND1\nEND1bend2", "Begin and end added part 4");

# offset with SEEK_END
my $origlength=length "$fh";
$fh->seek(3, SEEK_END);
is(length "$fh", $origlength + 3, "Seek beyond end should pad");
like("$fh", qr/END1bend2\0\0\0$/, 'Seek beyond end should pad (text match)');

$fh->add_or_replace_lines(qr/xxx/, qr/yyy/, 'End3', SEEK_END);
$fh->add_or_replace_lines(qr/xxx/, qr/yyy/, 'eNd4', SEEK_END, 3);
# add_after_newline, newline is added after the padding
like("$fh", qr/End3\0\0\0\neNd4$/, 'Add to end using whence END with offset part 3 and 4');


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

my ($start,$end) = $fh->get_header_positions();
$fh->add_or_replace_lines(qr/xxx/, qr/yyy/, "tsjoelala\n", SEEK_SET, $end);
like("$fh", qr/# tsjoelala tsjoelala\ntsjoelala\nwe goan hem/, 'Insert text after header');

my ($before, $after) = $fh->get_all_positions(qr{^tsjoelala.*$}m);
# ok, $after (and $before) is a reference to an array;
# if you pass it instead of eg $after->[0], you pass a very big number,
# creating a very big string
$fh->add_or_replace_lines(qr/xxx/, qr/yyy/, "tsjoelala\n", SEEK_SET, $after->[0]);
like("$fh", qr/# tsjoelala tsjoelala\ntsjoelala\ntsjoelala\nwe goan hem/, 'Insert text after matching line');

$fh->cancel();


done_testing();
