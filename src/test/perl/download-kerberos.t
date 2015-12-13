use strict;
use warnings;

use Test::More;
use Test::Quattor;
use CAF::Download::Kerberos;
use Test::Quattor::Object;
use Cwd;

my $obj = Test::Quattor::Object->new();

=pod

=head1 SYNOPSIS

Test all methods for C<CAF::Download::Kerberos>

=over

=item _initialize

=cut

my $k = CAF::Download::Kerberos->new(log => $obj);
isa_ok($k, 'CAF::Download::Kerberos', 'returns a CAF::Download::Kerberos instance');

done_testing();
