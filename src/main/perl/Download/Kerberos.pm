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

use GSSAPI;

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

# Based on CCM::Fetch::Download 15.12
sub _gss_die
{
    my ($func, $status) = @_;
    my $msg = "GSS Error in $func:\n";
    for my $e ($status->generic_message()) {
        $msg .= "  MAJOR: $e\n";
    }
    for my $e ($status->specific_message()) {
        $msg .= "  MINOR: $e\n";
    }
    die($msg);
}

# Based on from CCM::Fetch::Download 15.12
sub _gss_decrypt
{
    my ($self, $inbuf) = @_;

    my ($client, $status);
    my ($authtok, $buf) = unpack('N/a*N/a*', $inbuf);

    my $ctx = GSSAPI::Context->new();
    $status =
        $ctx->accept(GSS_C_NO_CREDENTIAL, $authtok, GSS_C_NO_CHANNEL_BINDINGS,
        $client, undef, undef, undef, undef, undef);
    $status or _gss_die("accept", $status);

    $status = $client->display(my $client_display);
    $status or _gss_die("display", $status);

    my $outbuf;
    $status = $ctx->unwrap($buf, $outbuf, 0, 0);
    $status or _gss_die("unwrap", $status);

    return ($client_display, $self->Gunzip($outbuf));
}


=pod

=back

=cut

1;
