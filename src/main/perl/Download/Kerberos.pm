# ${license-info}
# ${developer-info}
# ${author-info}
# ${build-info}

package CAF::Download::Kerberos;

use strict;
use warnings;

use parent qw(CAF::Object);
use Readonly;
use CAF::Object qw (SUCCESS);

=head1 NAME

CAF::Download::Kerberos - Class for Kerberos handling for L<CAF::Download>.

=head1 DESCRIPTION

This class handles validation/creation/destruction of Kerberos tickets and some
utitlities like kerberos en/decryption.

=cut

=head2 Methods

=over

=item C<_initialize>

Initialize the kerberos object. Arguments:

Optional arguments

=over

=item C<log>

A C<CAF::Reporter> object to log to.

=back

=cut

sub _initialize
{
    my ($self, %opts) = @_;

    $self->{log} = $opts{log} if $opts{log};

    return SUCCESS;
}

=pod

=back

=cut

1;
