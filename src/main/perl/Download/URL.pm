# ${license-info}
# ${developer-info}
# ${author-info}
# ${build-info}

package CAF::Download::URL;

use strict;
use warnings;

use parent qw(Exporter);
use Readonly;
use LC::Exception qw (SUCCESS);

our @EXPORT_OK = qw(set_url_defaults);

# Lots of undefs, because no good defaults
# But this is the list of defaults that one can set
# TODO: keep this in sync with pan type caf_url
Readonly::Hash my %URL_DEFAULTS => {
    auth => undef, # array ref of authentication schemes to try/use
    method => undef, # array ref of download methods to try/use
    proto => undef, # the protocol
    server => undef, # server to use
    filename => undef, # non-server part of the location

    #version => undef, # version information

    timeout => 600, # download timeout in seconds (600s * 1kB/s BW = 600kB document)
    head_timeout => undef, # timeout in seconds for initial request which checks for changes/existence

    retries => 3, # number retries
    retry_wait => 30, # number of seconds to wait before a retry

    krb5 => {
        principal => undef,
        realm => undef,
        components => undef, # array ref of components
        keytab => undef, # location of keytab to use
    },

    x509 => {
        cacert => undef, # CA file
        capath => undef, # CA directory
        cert => undef, # client cert file
        key => undef, # client key file
    },

    proxy => {
        server => undef,
        port => undef,
        reverse => undef, # reverse proxy (default is false, i.e. forward)
    },

};

# create deep copy of defaults as private copy
my $_url_defaults = {};
_merge_url($_url_defaults, \%URL_DEFAULTS, 1);

=head1 NAME

CAF::Download::Url - Class for URL handling for L<CAF::Download>.

=head1 DESCRIPTION

This class simplyfies handles the parsing, generation and validation
of URL to used withing L<CAF::Download>.

=cut

=head2 Functions

=over

=item set_url_defaults

Sets one or more url defaults accdoring to hashref C<defaults>.
Returns undef on failure, and (a copy of) the defaults on success.
Has no logging, and (as a function) no C<fail> attribute.

=cut

# Test if all keys are ok to set against URL_DEFAULTS.
# Teturn undef on failure, SUCCESS on success.
sub _is_valid_url
{
    my $url = shift;

    # 2 levels
    foreach my $k (sort keys %$url) {
        # ignore keys with starting with _
        next if ($k =~ m/^_/);

        return if (!exists($URL_DEFAULTS{$k}));
        if (ref($url->{$k}) eq 'HASH') {
            return if (grep {! exists($URL_DEFAULTS{$k}->{$_})} keys %{$url->{$k}});
        }
    }

    return SUCCESS;
}

# Given (valid) $url, return string representation
sub _to_string
{
    my $url = shift;

    my $txt = join('+',
                   @{$url->{auth} || []},
                   @{$url->{method} || []},
                   $url->{proto},
        );
    $txt .= "://";
    $txt .= $url->{server} || '';
    $txt .= $url->{filename} || '';

    return $txt;
}

# Merge 2 url hashrefs, the first url is updated in place.
# First checks if both urls are valid urls with the _is_valid_url check.
# If 3rd option update is set, existing key/value are overwritten,
# otherwise only missing key/values are added.
# Returns undef in case of failure, SUCCESS otherwise.
# You can use it as a deepcopy mechanism for urls by
# passing a variable that is an empty hashref as first argument.
sub _merge_url
{
    my ($url1, $url2, $update) = @_;

    return if ! (_is_valid_url($url1) && _is_valid_url($url2));

    foreach my $k (sort keys %$url2) {
        if (ref($url2->{$k}) eq 'HASH') {
            foreach my $k2 (sort keys %{$url2->{$k}}) {
                $url1->{$k}->{$k2} = $url2->{$k}->{$k2}
                    if ($update || ! exists($url1->{$k}->{$k2}));
            }
        } else {
            $url1->{$k} = $url2->{$k} if ($update || ! exists($url1->{$k}));
        };
    }

    return SUCCESS;
}

# Returning a copy of the default is mainly for unittesting
sub set_url_defaults
{
    my ($defaults) = @_;

    return if(! _merge_url($_url_defaults, $defaults, 1));

    # _merge_url will make a deep copy
    my $copy = {};
    return if (! _merge_url($copy, $_url_defaults, 1));

    return $copy;
}

=pod

=back

=head2 Methods

=over

=item C<parse_urls>

C<parse_urls> prepares the urls.

Returns 1 on success, undef in case of failure (and sets the C<fail> attribute).
No errors are logged.

The C<urls> is an array reference with each url

=over

=item a string

A literal URL, all details will extracted.

=item a hashref with possible keys

=over

=item auth

The arrayref of authentication schemes to try/use. Supported are

=over

=item gssapi

=item kinit

=item lwp

=back

=item method

The arrayref of download methods to try/use. Supported are

=over

=item lwp

=item curl

=back

=item proto

The protocol to use, supported are

=over

=item http

=item https

=item file

=back

=item server

The server to use (not valid when using C<file> protocol).

=item filename

The (non-server part of the) location of the to-be-downloaded file.

=item timeout

Download timeout in seconds (default 600).

=item head_timeout

Timeout in seconds for initial request which checks for changes/existence.

=item retries

The number retries (default 3). If undef, retry forever.

=item retry_wait

Number of seconds to wait before a retry (default 30).

=item krb5

Kerberos details, relevant for C<gssapi> and C<kinit> auth.

=over

=item principal

The kerberos principal.

=item realm

The kerberos realm.

=item components

The arrayref of kerberos components.

=item keytab

The location of the keytab to use.

=back

=item x509

=over

=item cacert

The filename of the CA certificate.

=item capath

The directory with one or more CA certificates.

=item cert

The client certificate filename.

=item key

The filename for the private key.

=back

=item proxy

Proxy settings

=over

=item server

Proxy server hostname.

=item port

Proxy server port number

=item reverse

Boolean, indicating this is a reverse proxy (default/undef is false, i.e. forward proxy)

=back

=back

=back

Returns the new array ref with completed url hashrefs on success,
undef in case of failure (and sets the C<fail> attribute).
No errors are logged.

=cut

sub parse_urls
{
    my ($self, $urls) = @_;

    my @newurls;

    foreach my $url (@$urls) {
        my $ref = ref($url);
        if($ref eq '') {
            # a string
            $url = $self->parse_url_string($url);
            # parse_url_string sets fail attribute already
            return if (! defined($url));
        } elsif ($ref eq 'HASH') {
            if(! _is_valid_url($url)) {
                return $self->fail("Cannot parse invalid url hashref.");
            }
        } else {
            return $self->fail("Url has wrong type $ref.");
        }

        # add defaults
        if (! _merge_url($url, $_url_defaults, 0)) {
            # a valid url that can't be merged with defaults, not sure what that could be
            return $self->fail("Unable to merge url with url defaults.");
        };

        $url->{_string} = _to_string($url);
        $url->{_id} = scalar(@newurls);

        push(@newurls, $url);
    }

    return \@newurls;
}

=pod

=item parse_url_string

Convert a string representing a URL into a hashref. It does not set the defaults.

The format is C<[auth+][method+]protocol://location> with

=over

=item protocol: one of

=over

=item http

=item file

=back

=item method: download method, one of

=over

=item lwp

=item curl

=back

=item auth: authentication, one of

=over

=item kinit

=item gssapi

=item x509

=back

=item location: the location string with following restrictions

=over

=item if the protocol is file, the location has to start with a /

=back

=back

It follows the pan type C<caf_url_string> from C<quattor/types/download>.
Returns undef in case of problem, with C<fail> attribute set.

=cut

# TODO: keep the type and this method in sync

sub parse_url_string
{
    my ($self, $text) = @_;

    my $url = {};

    my ($mp, $location, @remainder) = split('://', $text);

    if (!defined($location) || @remainder) {
        return $self->fail("Invalid URL string, requires :// (got $text)");
    };

    if($mp =~ m/^(?:(kinit|gssapi|x509)\+)?(?:(lwp|curl)\+)?(https?|file)$/) {
        $url->{auth} = [$1] if $1;
        $url->{method} = [$2] if $2;
        $url->{proto} = $3;
    } else {
        return $self->fail("Invalid auth+method+protocol for $mp");
    };

    if ($url->{proto} eq 'file') {
        if ($location =~ m/^\/.+/) {
            $url->{filename} = $location;
        } else {
            # / cannot be a filename for file
            return $self->fail("location for file protocol has to start with /, got $location");
        }
    } else {
        if ($location =~ qr{^([^/]+)(\/.*)}) {
            $url->{server} = $1;
            $url->{filename} = $2;
        } else {
            return $self->fail("location for $url->{proto} protocol has to start with a server, got $location");
        }
    };

    if(! _is_valid_url($url)) {
        return $self->fail("parse_url_string generated an invalid url. (Please report this bug)");
    }

    return $url;
}

=pod

=back

=cut

1;
