use strict;
use warnings;
use Test::More;
use Test::Quattor;
use CAF::Download;
use CAF::Download::URL qw(set_url_defaults);
use Test::MockModule;
use Cwd;

=pod

=head1 SYNOPSIS

Test all methods for C<CAF::Download::URL>

=over

=item _is_valid_url

=cut

ok(!defined(CAF::Download::URL::_is_valid_url({invalid => 'value', server => 'myserver'})),
   "invalid key returns invalid url 1st level");
ok(!defined(CAF::Download::URL::_is_valid_url({invalid => {whatever => 'value'}, server => 'myserver'})),
   "invalid key returns invalid url 1st level bis");
ok(!defined(CAF::Download::URL::_is_valid_url({krb5 => {whatever => 'value'}, server => 'myserver'})),
   "invalid key returns invalid url 2nd level");
ok(CAF::Download::URL::_is_valid_url({server => 'myserver'}),
   "valid 1st level");
ok(CAF::Download::URL::_is_valid_url({krb5 => {realm => 'VALUE'}, server => 'myserver'}),
   "valid 2nd level");

=item _merge_url

=cut

my $validurl1 = {krb5 => {realm => 'VALUE'}, server => 'myserver'};
# the same as 1
my $validurl1b = {krb5 => {realm => 'VALUE'}, server => 'myserver'};
is_deeply($validurl1, $validurl1b, "same valid url1");

my $invalidurl1 = {xkrb5 => {realm => 'VALUE'}, server => 'myserver'};
ok(! defined(CAF::Download::URL::_is_valid_url($invalidurl1)),
   "invalidurl1 is not valid");

my $validurl2 = {x509 => {capath => 'value'}, filename => 'somepath'};
# the same as 2
my $validurl2b = {x509 => {capath => 'value'}, filename => 'somepath'};
is_deeply($validurl2, $validurl2b, "same valid url2");

my $invalidurl2 = {x509 => {capath => 'value'}, xfilename => 'somepath'};
ok(! defined(CAF::Download::URL::_is_valid_url($invalidurl2)),
   "invalidurl2 is not valid");

my $res = CAF::Download::URL::_merge_url($invalidurl1, $validurl2);
diag explain $res;
ok(!defined($res),
   "can't merge if 1st arg is invalid url");
is_deeply($validurl1, $validurl1b, "unmodified url1 after failure arg1");
is_deeply($validurl2, $validurl2b, "unmodified url2 after failure arg1");

ok(!defined(CAF::Download::URL::_merge_url($validurl1, $invalidurl2)),
   "can't merge if 2nd arg is invalid url");
is_deeply($validurl1, $validurl1b, "unmodified url1 after failure arg2");
is_deeply($validurl2, $validurl2b, "unmodified url2 after failure arg2");

ok(CAF::Download::URL::_merge_url($validurl1, $validurl2),
   "can merge url1 and url1");

# do the merge by hand
$validurl1b->{filename} = $validurl2->{filename};
$validurl1b->{x509} = {%{$validurl2->{x509}}};

is_deeply($validurl1, $validurl1b, "modified url1 with correct value after merge");
is_deeply($validurl2, $validurl2b, "unmodified url2 after merge");

=item set_url_defaults

=cut

my $orig_defaults = set_url_defaults();
ok(!defined(set_url_defaults({
    invalidkey => 'value',
    server => 'myserver'})),
   "set_urls_defaults returns undef on invalid key");
is_deeply(set_url_defaults(), $orig_defaults,
          "no defaults changed when set_url_defaults fails");
ok(set_url_defaults({server => 'myserver'}), "Set new url_default ok");
is(set_url_defaults()->{server}, 'myserver', 'new default value is set');

# 2 levels deep

$orig_defaults = set_url_defaults();
ok(!defined(set_url_defaults({
    krb5 => { invalidkey => 'value'},
    server => 'myserverother'})),
   "set_urls_defaults returns undef on invalid key on 2nd level");
is_deeply(set_url_defaults(), $orig_defaults,
          "no defaults changed when set_url_defaults fails on 2nd level");
ok(set_url_defaults({server => 'myotherserver', krb5 => { realm => 'TEST.ORG' }}), 
   "Set new url_default ok on 2nd level");
is(set_url_defaults()->{server}, 'myotherserver', 'new default value is set on 1st level');
is(set_url_defaults()->{krb5}->{realm}, 'TEST.ORG', 'new default value is set on 2nd level');

#
# Init instance for method testing
#
my $d = CAF::Download->new("/tmp/dest", ["http://localhost"]);
isa_ok($d, 'CAF::Download', 'is a CAF::Download instance');

=pod

=item parse_url_string

=cut

my $iurl_req = qr{^Invalid URL string, requires ://};
my $iurl_proto = qr{^Invalid auth\+method\+protocol};

my $fail_url_string = {
    '' => $iurl_req,
    'location' => $iurl_req,
    'proto://' => $iurl_req,
    'file://location://location2' => $iurl_req,

    'a+b+c://a' => $iurl_proto,
    'httpd://a' => $iurl_proto,
    'something+http://a' => $iurl_proto,
    'someything+lwp+http://a' => $iurl_proto,
    'lwp+krb5+http://a' => $iurl_proto, # first auth, then method

    'file://a/b/c' => qr{^location for file protocol has to start with /,},

    'https:///ab/c/' => qr{^location for https protocol has to start with a server},
};
while (my ($str, $failre) = each %$fail_url_string) {
    $d->{fail} = undef;
    ok(! defined($d->parse_url_string($str)), "Invalid URL string $str");
    like($d->{fail}, $failre, "Invalid URL string failed with message $d->{fail}");
};


# generate valid urls
my $server = "myserver";

foreach my $proto (qw(file http https)) {
    foreach my $method (qw(UNDEF lwp curl)) {
        foreach my $auth (qw(UNDEF kinit gssapi x509)) {
            foreach my $fn (qw(/ /some/path)) {
                my $urlstr = '';
                my $res = {};
                if ($auth ne 'UNDEF') {
                    $urlstr .= "$auth+";
                    $res->{auth} = [$auth];
                };

                if ($method ne 'UNDEF') {
                    $urlstr .= "$method+";
                    $res->{method} = [$method];
                };

                $urlstr .= "$proto://";
                $res->{proto} = $proto;

                if ($proto ne 'file') {
                    $urlstr .= $server;
                    $res->{server} = [$server];
                }

                # file with / as filename is not valid, skip it
                next if ($proto  eq 'file' && $fn eq '/');

                $urlstr .= $fn;
                $res->{filename} = $fn;

                is_deeply($d->parse_url_string($urlstr), $res,
                          "parser url string $urlstr");
            }
        }
    }
}

# verify string or hashref
# verify inheritance of global defaults

=pod

=back

=cut

done_testing();
