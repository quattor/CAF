# ${license-info}
# ${developer-info}
# ${author-info}
# ${build-info}

package CAF::Download::Retrieve;

use strict;
use warnings;

use Readonly;
use LC::Exception qw (SUCCESS);

Readonly my $MAX_RETRIES => 1000;

=head1 NAME

CAF::Download::Retrieve - Class for retrieval for L<CAF::Download>.

=head1 DESCRIPTION

This class handles the downloading of the URLs to use within L<CAF::Download>.

=cut

=head2 Functions

=over

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

    # setup auth
    # prep local ENV via env attr
    # run method
    # cleanup auth

    return SUCCESS;
}

=pod

=back

=cut

1;
