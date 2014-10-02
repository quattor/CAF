# -*- perl -*-
#!/usr/bin/perl
use strict;
use warnings;
use FindBin qw($Bin);
use lib "$Bin/";
use testapp;
use CAF::FileReader;
use Test::More;
use Carp qw(confess);
use CAF::FileEditor;

=pod

=head1 SYNOPSIS

Trivial test for C<CAF::FileReader>

=cut

use constant TEXT => <<EOF;
En un lugar de La Mancha, de cuyo nombre no quiero acordarme...
EOF

our $text = TEXT;

my $fh = CAF::FileReader->open("/etc/resolv.conf");

isa_ok($fh, "CAF::FileReader");
ok("$fh", "Contents are read");
is("$fh", TEXT, "Expected contents are read");


done_testing();
