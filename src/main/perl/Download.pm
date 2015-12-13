# ${license-info}
# ${developer-info}
# ${author-info}
# ${build-info}

package CAF::Download;

use strict;
use warnings;

# For re-export only
use CAF::Download::URL qw(set_url_defaults);
use parent qw(CAF::ObjectText Exporter CAF::Download::URL CAF::Download::Retrieve);

use Readonly;
use LC::Exception qw (SUCCESS);

our @EXPORT_OK = qw(set_url_defaults);

# TODO: dependencies on curl and kinit

Readonly::Hash my %DOWNLOAD_METHODS => {
    http => [qw(lwp curl)], # try https, if not, try http
    https => [qw(lwp curl)], # only https
    file => [qw(lwp)],
};

Readonly::Array my @DOWNLOAD_PROTOCOLS => sort keys %DOWNLOAD_METHODS;

# TODO: can we mix and match x509/krb5 also for security like TLS?
# The GSSAPI doesn't require TLS, it has encryption
# gssapi here means use the perl GSSAPI bindings to generate the tokens etc
# kinit means to use commandline tools like kinit/kdestroy
# x509/lwp means have LWP handle X509 (TLS + X509 auth)
# TODO: does kinit imply GSSAPI usage?
Readonly::Hash my %DOWNLOAD_AUTHENTICATION => {
    krb5 => [qw(gssapi kinit)],
    x509 => [qw(lwp)],
};

# Disclaimer: inspired by
#    NCM::Component::download (15.8)
#    EDG::WP4::CCM::Fetch (15.8)
#    File::Fetch (0.48)

=pod

=head1 NAME

CAF::Download - Class for downloading content from remote servers.

=head1 SYNOPSIS

    use CAF::Download;

    my $dl = CAF::Download->new(['https://somewhere/myfile']);
    print "$dl"; # stringification

    $dl = CAF::TextRender->new(['https://somewhere/else']);
    # return CAF::FileWriter instance (downloaded text already added)
    my $fh = $dl->filewriter('/some/path');
    die "Problem downloading the data" if (!defined($fh));
    $fh->close();

=head1 DESCRIPTION

This class simplyfies the downloading of content located on remote servers.
It handles things like authentication, decryption, creating the actual file, ...

=head2 Methods

=over

=item C<_initialize>

Initialize the download object. Arguments:

=over

=item urls

A array reference of urls. Urls will be tried in order, first successful
one is used. Providing more than one url can thus be used for failover.

See C<prepare_urls> method for a description off the C<urls>.

=back

It takes some extra optional arguments:

=over

=item C<log>

A C<CAF::Reporter> object to log to.

=item C<setup>

Boolean to run the setup (or not). Default/undef is to run setup.

=item C<cleanup>

Boolean to run the cleanup (or not). Default/undef is to run cleanup.

=item destination

The destination of the download, e.g. a filename. This is in particular required
for download methods that can write to file themself, like C<curl>.

=back

=cut

sub _initialize
{
    my ($self, $urls, %opts) = @_;

    $self->{urls} = $self->parse_urls($urls);

    %opts = () if !%opts;

    $self->_initialize_textopts(%opts);

    $self->{setup} = (! defined($opts{setup}) || $opts{setup}) ? 1 : 0;
    $self->{cleanup} = (! defined($opts{cleanup}) || $opts{cleanup}) ? 1 : 0;
    $self->debug(1, "setup $self->{setup} cleanup $self->{cleanup}");

    if ($opts{destination}) {
        $self->{destination} = $self->prepare_destination($opts{destination});
        $self->debug(1, "download destination set to " . ($self->{destination} || '<UNDEF>'));
    }

    return SUCCESS;
}

=pod

=back

=cut

1;
