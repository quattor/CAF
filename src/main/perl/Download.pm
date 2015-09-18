# ${license-info}
# ${developer-info}
# ${author-info}
# ${build-info}

package CAF::Download;

use strict;
use warnings;

# For re-export only
use CAF::Download::URL qw(set_url_defaults);
use parent qw(CAF::Object Exporter CAF::Download::URL);

use Readonly;
use LC::Exception qw (SUCCESS);

our @EXPORT_OK = qw(set_url_defaults);

# TODO: dependencies on curl and kinit

Readonly my $MAX_RETRIES => 1000;

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

# Handle failures. Stores the error message and log it verbose and
# returns undef. All failures should use 'return $self->fail("message");'.
# No error logging should occur in this module.
sub fail
{
    my ($self, @messages) = @_;
    $self->{fail} = join('', @messages);
    $self->verbose("FAIL: ", $self->{fail});
    return;
}

# Disclaimer: inspired by
#    NCM::Component::download (15.8)
#    EDG::WP4::CCM::Fetch (15.8)
#    File::Fetch (0.48)

=pod

=head1 NAME

CAF::Download - Class for downloading content from remote servers.

=head1 SYNOPSIS

    use CAF::Download;

=head1 DESCRIPTION

This class simplyfies the downloading of content located on remote servers.
It handles things like authentication, decryption, creating the actual file, ...

=head2 Methods

=over

=item C<_initialize>

Initialize the process object. Arguments:

=over

=item destination

The destination of the download, e.g. a filename.

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

=back

=cut

sub _initialize
{
    my ($self, $destination, $urls, %opts) = @_;

    $self->{destination} = $self->prepare_destination($destination);
    $self->{urls} = $self->parse_urls($urls);

    %opts = () if !%opts;

    $self->{log} = $opts{log} if $opts{log};

    $self->{setup} = (! defined($opts{setup}) || $opts{setup}) ? 1 : 0;
    $self->{cleanup} = (! defined($opts{cleanup}) || $opts{cleanup}) ? 1 : 0;
    $self->debug(1, "setup $self->{setup} cleanup $self->{cleanup}");

    return SUCCESS;
}

=pod

=item C<prepare_destination>

C<prepare_destination> prepares the destination.

Returns the prepared destination on success, undef in case of failure (and sets the C<fail> attribute).
No errors are logged.

=cut

# TODO: e.g. mkdir, check write rights, tempdir, in case there's no intermediate file...

sub prepare_destination
{
    my ($self, $destination) = @_;

    return $destination;
}

=pod

=item download

Download the data from the url(s) to the destination.
In case a retrieval fails, the following url is tried. If there are no more urls to try,
it will reiterate over the original list of urls, and this maximum C<retries> time per url,
with a C<retry_wait> wait interval before each retry.

Returns SUCCESS on succes, undef in case of failure (and sets the C<fail> attribute).
No errors are logged.

=cut

sub download
{
    my ($self) = @_;

    # in case the prepare_destination failed. fail attribute is set
    return if (!defined($self->{destination}));

    # in case the parse_urls failed. fail attribute is set
    return if (!defined($self->{urls}));


    my %tried; # per-url retry counter
    my $tries = 0; # total tries

    # a weak copy, so we can push/shift without changing original list of urls
    my @urls = @{$self->{urls}};

    while (@urls) {
        my $url = shift @urls;

        my $txt = $url->{_string};
        my $id = $url->{_id};

        $self->verbose("download url $txt (id $id) attempt ",
                       ($tried{$id} || 0) + 1,
                       " total attempts $tries.");

        # TODO: should we really wait if we try another url?
        #       only wait on actual retry of same url(s)?
        # first attempt of first url does not get a retry wait
        my $wait = $url->{retry_wait};
        if($tries && $wait) {
            $self->debug(1, "sleep retry_wait $wait url $txt id $id");
            sleep($wait);
        };

        # loop over auths and methods
        # TODO: no waits here?
        foreach my $method (@{$url->{method}}) {
            foreach my $auth (@{$url->{auth}}) {
                return SUCCESS if($self->retrieve($url, $method, $auth));
                # TODO: warn or verbose the failures?
            }
        }

        # tried this url
        $tried{$id}++;

        # if retries is not defined, try forever
        # everything is limited by MAX_RETRIES (to avoid infinite loops)
        if ((! defined($url->{retries})) || $tried{$id} < $url->{retries}) {
            if ($tried{$id} >= $MAX_RETRIES) {
                $self->warn("MAX_RETRIES $MAX_RETRIES reached for url $txt (ud $id).");
            } else {
                push(@urls, $url);
            }
        } else {
            $self->verbose("Not retrying url $txt (id $id) anymore");
        }
        $tries++;
    }

    return $self->fail("download failed: no more urls to try (total attempts $tries).");
}

=pod

=item retrieve

Retrieve a single C<$url> using method C<$method> and authentication C<$auth>.
(The C<method> and C<auth> attributes of the url are ignored).

Returns SUCCESS on succes, undef in case of failure (and sets the C<fail> attribute).
No errors are logged.

=cut

sub retrieve
{
    my ($self, $url, $method, $auth) = @_;

    return SUCCESS;
}

=pod

=back

=cut

1;
