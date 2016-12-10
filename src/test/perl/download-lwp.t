use strict;
use warnings;

use Test::More;
use Test::MockModule;

BEGIN {
    use LWP::UserAgent;

    # aka "recent enough"
    $LWP::UserAgent::VERSION = '5.833';

    %ENV = (
        PERL_NET_HTTPS_SSL_SOCKET_CLASS => 'woohaha',
        SOMETHING_ELSE => 'else',
        );
    diag "original env ", explain \%ENV;
};

use CAF::Download::LWP;
use Test::Quattor::Object;

use Test::MockModule;

my $mock = Test::MockModule->new('LWP::UserAgent');
# Return the ENV, make sure we don't use the one that is local in this test
my $timeout;
my $newopts;
$mock->mock('new', sub {
    my ($self, %opts) = @_;
    $newopts = \%opts;
    my $init = $mock->original("new");
    return &$init($self, %opts);
});
$mock->mock('timeout', sub {shift; $timeout = shift;});
$mock->mock('testenv', sub {shift;return [\@_, eval '\%ENV']});

my $obj = Test::Quattor::Object->new();

is_deeply(\%ENV, {
    PERL_NET_HTTPS_SSL_SOCKET_CLASS => undef,
    SOMETHING_ELSE => 'else',
}, "test local ENV as expected 0");

my $lwp = CAF::Download::LWP->new(log => $obj);
isa_ok($lwp, "CAF::Download::LWP", "got a CAF::Download::LWP instance");

ok(! defined($ENV{PERL_NET_HTTPS_SSL_SOCKET_CLASS}), "PERL_NET_HTTPS_SSL_SOCKET_CLASS ENV not set");

$timeout = -1;
$newopts = undef;
my $ua = $lwp->_get_ua(
    cacert => 'cacert',
    cadir => 'cadir',
    ccache => 'abc',
    cert => 'cert',
    key => 'key',
    timeout => 5,
);
isa_ok($ua, 'LWP::UserAgent', 'got a LWP::UserAgent instance');
is_deeply(\%ENV, {
    PERL_NET_HTTPS_SSL_SOCKET_CLASS => undef,
    SOMETHING_ELSE => 'else',
          }, "test local ENV as expected 1");

is_deeply($lwp->{ENV}, {
    PERL_LWP_SSL_VERIFY_HOSTNAME => 1,
    PERL_NET_HTTPS_SSL_SOCKET_CLASS => undef,
    KRB5CCNAME => 'abc',
}, 'lwp ENV atttribute as expected');
is($timeout, 5 , "timeout set on lwp");
is_deeply($newopts, {
    ssl_opts => {
        # no CA dir when cacert is specified
        SSL_ca_file => 'cacert',
        SSL_cert_file => 'cert',
        SSL_key_file => 'key',
        verify_hostname => 1,
    },
}, "LWP::UserAgent called with expected options");

delete $lwp->{ENV};
is_deeply($lwp->_do_ua('testenv', [qw(arg1 arg2)], key => 'key2'), [
              [qw(arg1 arg2)],{
                  PERL_LWP_SSL_VERIFY_HOSTNAME => 1,
                  SOMETHING_ELSE => 'else',
              }], "mocked testenv method call returned passed args and expected env");
is_deeply(\%ENV, {
    PERL_NET_HTTPS_SSL_SOCKET_CLASS => undef,
    SOMETHING_ELSE => 'else',
}, "test local ENV as expected 2");

done_testing();
