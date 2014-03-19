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
$fh->add_or_replace_lines(qr/xxx/, qr/yyy/, 'BEGIN1', BEGINNING_OF_FILE);
like("$fh", qr/^BEGIN1/, 'Initial beginning using predefined constants');

# expert mode
$fh->add_or_replace_lines(qr/xxx/, qr/yyy/, 'begin2', SEEK_SET);
like("$fh", qr/^begin2/, 'Add to begin using whence SET (default offset)');

# go to pos 5
$fh->add_or_replace_lines(qr/xxx/, qr/yyy/, 'Begin3', SEEK_SET, 5);
like("$fh", qr/^beginBegin3/, 'Add to begin using whence SET with offset');

# ok, let the bizare stuff begin
# go to position 5 from the beginning
$fh->seek(5, SEEK_SET);
# add to the current position with an extra offset of 5
$fh->add_or_replace_lines(qr/xxx/, qr/yyy/, 'bEgIn4', SEEK_CUR, 5);
like("$fh", qr/^beginBeginbEgIn4/, 'CUR whence with offset 5 (after seek 5)');

$fh->cancel();

use constant TEXT => <<'EOF';
We goan em zn broek afdoen
tsjoelala tsjoelala
we goan hem zn broek afdoen
tsjoe
la
la
EOF

$fh = CAF::FileEditor->new ($filename);
$fh->set_contents(TEXT);
$fh->cancel();


done_testing();
