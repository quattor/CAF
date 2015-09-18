use strict;
use warnings;

use Test::More;
use Test::Quattor;
use CAF::Download qw(set_url_defaults);
use Test::Quattor::Object;
use Cwd;

my $obj = Test::Quattor::Object->new();

=pod

=head1 SYNOPSIS

Test all methods for C<CAF::Download>

=over

=item _initialize

=cut


my $d = CAF::Download->new("/tmp/dest", ["http://localhost"], log => $obj);
isa_ok($d, 'CAF::Download', 'is a CAF::Download instance');
is($d->{setup}, 1, "default setup is 1");
is($d->{cleanup}, 1, "default cleanup is 1");

$d = CAF::Download->new("/tmp/dest", ["http://localhost"], setup => 0, cleanup => 0, log => $obj);
isa_ok($d, 'CAF::Download', 'is a CAF::Download instance');
is($d->{setup}, 0, "setup disabled / set to 0");
is($d->{cleanup}, 0, "cleanup disabled / set to 0");

done_testing();
