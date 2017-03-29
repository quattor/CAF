=pod

=head1 SYNOPSIS

Old mock module emulating LC::Check::file, for CAF:: tests.
It is now replaced by mocked File::AtomicWrite module.

This module should not be used in CAF anymore.

=cut

package LC::Check;

our $VERSION = '1.22';

sub file
{
    die "Mocked LC::Check::file from resources/LC should not be used anymore";
}

1;
