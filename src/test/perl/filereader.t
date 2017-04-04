# -*- perl -*-

use strict;
use warnings;
use FindBin qw($Bin);
use lib "$Bin/modules";
use testapp;
use CAF::FileWriter;
use CAF::FileReader;
use Test::More;

=pod

=head1 SYNOPSIS

Trivial test for C<CAF::FileReader>

=cut

use constant TEXT => <<EOF;
En un lugar de La Mancha, de cuyo nombre no quiero acordarme...
EOF

our $text = TEXT;

# file must exist, even offline
my $fh = CAF::FileReader->new("/etc/hosts");

isa_ok($fh, "CAF::FileReader");
ok("$fh", "Contents are read");
is("$fh", TEXT, "Expected contents are read");
is(*$fh->{save}, 0, "Modifications to the file won't be saved");

ok(!defined($fh->close()), "close returns undef");
is(*$fh->{original_content}, TEXT, "latest content saved as (new) original_content after close");

$fh->reopen();
ok($fh->opened(), "file is open again after reopen");
is("$fh", TEXT, "Expected contents after reopen");


done_testing();
