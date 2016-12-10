#${PMpre} CAF::Download::LWP${PMpost}

=pod

=head1 NAME

C<CAF::Download::LWP> class to use C<LWP> (and C<Net::HTTPS>).

=head1 DESCRIPTION

C<CAF::Download::LWP> prepares C<LWP> (and C<Net::HTTPS>) and
provides interface to C<LWP::UserAgent>.

=head1 METHODS

=over

=cut

use parent qw(CAF::Object);

use Readonly;

# Lexical scope for Readonly set in BEGIN{}
my ($HTTPS_CLASS_NET_SSL, $HTTPS_CLASS_IO_SOCKET_SSL, $LWP_MINIMAL, $LWP_CURRENT);
# Keep track of default class from BEGIN
my $_default_https_class;

# This is the main variable that should be set asap.
# It is relevant for Net::HTTPS;
# first module to import it wins.
local $ENV{PERL_NET_HTTPS_SSL_SOCKET_CLASS} = $ENV{PERL_NET_HTTPS_SSL_SOCKET_CLASS};

BEGIN {
    Readonly $HTTPS_CLASS_NET_SSL => 'Net::SSL';
    Readonly $HTTPS_CLASS_IO_SOCKET_SSL => 'IO::Socket::SSL';

    # From the el6 perl-libwww-perl changelog:
    #   Implement hostname verification that is disabled by default. You can install
    #   IO::Socket::SSL Perl module and set PERL_LWP_SSL_VERIFY_HOSTNAME=1
    #   enviroment variable (or modify your application to set ssl_opts option
    #   correctly) to enable the verification.
    # So this version supports ssl_opts and supports verify_hostname for IO::Socket::SSL
    Readonly $LWP_MINIMAL => version->new('5.833');

    # This does not load Net::HTTPS by itself
    use LWP::UserAgent;
    $_default_https_class = $HTTPS_CLASS_NET_SSL;
    my $vtxt = $LWP::UserAgent::VERSION;
    if ($vtxt && $vtxt =~ m/(\d+\.\d+)/) {

        Readonly $LWP_CURRENT => version->new($1);

        if ($LWP_CURRENT >= $LWP_MINIMAL) {
            # Use system defaults
            $_default_https_class = undef;
        }
    }

    # This doesn't do anything on EL5?
    $ENV{PERL_NET_HTTPS_SSL_SOCKET_CLASS} = $_default_https_class;
}

# Keep this outside the BEGIN{} block
use Net::HTTPS;

# Support kerberised http
use LWP::Authen::Negotiate;

=item C<_initialize>

Initialize the object.

Optional arguments:

=over

=item C<log>

A C<CAF::Reporter> object to log to.

=back

=cut

sub _initialize
{
    my ($self, %opts) = @_;

    $self->{log} = $opts{log} if $opts{log};
}

=item _get_ua

Prepare the environment and initialise C<LWP::UserAgent>.
Best-effort to handle ssl setup, C<Net::SSL> vs C<IO::Socket::SSL>
and C<verify_hostname>.

Example usage
    ...
    my $ua = $self->_get_ua(%opts);

    local %ENV = %ENV;
    $self->update_env(\%ENV);
    ...

Returns the C<LWP::UserAgent> instance or undef.

Options

=over

=item cacert: the CA file

=item cadir: the CA path

=item cert: the client certificate filename

=item key: the client certificate private key filename

=item ccache: the kerberos crednetial cache

=item timeout: set timeout

=back

=cut


sub _get_ua
{
    my ($self, %opts) = @_;

    # This is a mess.

    # Set this again; very old Net::HTTPS (like in EL5) does not set the class
    # on the initial import in the BEGIN{} section
    $self->{ENV}->{PERL_NET_HTTPS_SSL_SOCKET_CLASS} = $_default_https_class;

    my $https_class = $Net::HTTPS::SSL_SOCKET_CLASS;
    if ($_default_https_class && $https_class ne $_default_https_class) {
        # E.g. when LWP was already used by previous component
        # No idea how to properly change/force it to the class we expect
        $self->warn("Unexpected Net::HTTPS SSL_SOCKET_CLASS: found $https_class, expected $_default_https_class");
    } else {
        $self->debug(3, "Using Net::HTTPS SSL_SOCKET_CLASS $https_class");
    }

    my %lwp_opts;

    # Disable by default, for legacy reasons and because
    # Net::SSL does not support it (even in el7)
    my $verify_hostname = 0;

    if (!defined($LWP_CURRENT)) {
        $self->verbose("Invalid LWP::UserAgent version ",
                       ($LWP::UserAgent::VERSION || '<undef>'),
                       " found. Assuming very ancient system");
    } elsif ($LWP_CURRENT >= $LWP_MINIMAL) {
        $self->debug(3, "Using LWP::UserAgent version $LWP_CURRENT");
        if ($https_class eq $HTTPS_CLASS_IO_SOCKET_SSL) {
            $self->debug(2, "LWP::UserAgent is recent enough to support verify_hostname for $HTTPS_CLASS_IO_SOCKET_SSL");
            $verify_hostname = 1;
        };

        my $ssl_opts = {
            verify_hostname => $verify_hostname,
        };

        $ssl_opts->{SSL_ca_file} = $opts{cacert} if $opts{cacert};
        if ($opts{cadir}) {
            if ($opts{cacert}) {
                $self->verbose("Both cacert and cadir passed, using only cacert $opts{cacert}, ",
                               "ignoring cadir $opts{cadir}");
            } else {
                $ssl_opts->{SSL_ca_path} = $opts{cadir} ;
            };
        }
        $ssl_opts->{SSL_cert_file} = $opts{cert} if $opts{cert};
        $ssl_opts->{SSL_key_file} = $opts{key} if $opts{key};

        $self->debug(3, "Using LWP::UserAgent ssl_opts ", join(" ", map {"$_: ".$ssl_opts->{$_}} sort keys %$ssl_opts));
        $lwp_opts{ssl_opts} = $ssl_opts;
    }

    # ssl_opts override any environment vars; but just in case
    $self->{ENV}->{PERL_LWP_SSL_VERIFY_HOSTNAME} = $verify_hostname;

    if ($https_class eq $HTTPS_CLASS_NET_SSL) {
        # Probably not needed anymore in recent version,
        # they are set via ssl_opts
        # But this just in case (e.g. EL5)
        $self->{ENV}->{HTTPS_CERT_FILE} = $opts{cert} if $opts{cert};
        $self->{ENV}->{HTTPS_KEY_FILE} = $opts{key} if $opts{key};

        # What do these do in EL5?
        $self->{ENV}->{HTTPS_CA_FILE} = $opts{cacert} if $opts{cacert};
        $self->{ENV}->{HTTPS_CA_DIR} = $opts{capath} if $opts{capath};
    } elsif ($https_class eq $HTTPS_CLASS_IO_SOCKET_SSL) {
        # nothing needed?
        # one could try to set the IO::Socket::SSL::set_ctx_defaults
        # see http://stackoverflow.com/questions/74358/how-can-i-get-lwp-to-validate-ssl-server-certificates#5329129
        # but el6 changelog says this is not necessary
    } else {
        # This is not supported
        $self->error("Unsupported Net::HTTPS SSL_SOCKET_CLASS $https_class");
        return;
    }

    # Required for LWP::Authen::Negotiate
    $self->{ENV}->{KRB5CCNAME} = $opts{ccache} if $opts{ccache};

    # unclear if the enviroment is needed diuring init and/or during usage
    # set it in both cases, to be on the safe side
    local %ENV = %ENV;
    $self->update_env(\%ENV);
    my $lwp = LWP::UserAgent->new(%lwp_opts);
    $lwp->timeout($opts{timeout}) if (defined($opts{timeout}));

    return $lwp;
}

=item _do_ua

Initialise C<LWP::UserAgent> using C<_get_ua> method
and run C<method> with arrayref C<args>.

All named options are passed to C<_get_ua>.

=cut

sub _do_ua
{
    my ($self, $method, $args, %opts) = @_;

    my $lwp = $self->_get_ua(%opts);

    local %ENV = %ENV;
    $self->update_env(\%ENV);
    my $res = $lwp->$method(@$args);

    return $res;
}


=pod

=back

=cut

1;
