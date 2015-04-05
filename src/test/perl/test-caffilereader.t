# -*- perl -*-

use strict;
use warnings;
use lib 'src/test/resources';
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

my $fh = CAF::FileReader->new("/etc/resolv.conf");

isa_ok($fh, "CAF::FileReader");
ok("$fh", "Contents are read");
is("$fh", TEXT, "Expected contents are read");
is(*$fh->{save}, 0, "Modifications to the file won't be saved");

done_testing();
