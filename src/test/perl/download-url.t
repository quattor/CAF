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

my $validurl1 = {krb5 => {realm => 'VALUE'}, server => 'myserver', filename => '/somepath1'};
# the same as 1
my $validurl1b = {krb5 => {realm => 'VALUE'}, server => 'myserver', filename => '/somepath1'};
my $validurl1c = {krb5 => {realm => 'VALUE'}, server => 'myserver', filename => '/somepath1'};
is_deeply($validurl1, $validurl1b, "same valid url1");
is_deeply($validurl1, $validurl1c, "same valid url1 (2nd time)");

my $invalidurl1 = {xkrb5 => {realm => 'VALUE'}, server => 'myserver', filename => '/somepath1'};
ok(! defined(CAF::Download::URL::_is_valid_url($invalidurl1)),
   "invalidurl1 is not valid");

my $validurl2 = {x509 => {capath => 'value'}, filename => '/somepath2'};
# the same as 2
my $validurl2b = {x509 => {capath => 'value'}, filename => '/somepath2'};
is_deeply($validurl2, $validurl2b, "same valid url2");

my $invalidurl2 = {x509 => {capath => 'value'}, xfilename => '/somepath2'};
ok(! defined(CAF::Download::URL::_is_valid_url($invalidurl2)),
   "invalidurl2 is not valid");

my $res = CAF::Download::URL::_merge_url($invalidurl1, $validurl2, 1);
diag explain $res;
ok(!defined($res),
   "can't merge if 1st arg is invalid url");
is_deeply($validurl1, $validurl1b, "unmodified url1 after failure arg1");
is_deeply($validurl2, $validurl2b, "unmodified url2 after failure arg1");

ok(!defined(CAF::Download::URL::_merge_url($validurl1, $invalidurl2, 1)),
   "can't merge if 2nd arg is invalid url");
is_deeply($validurl1, $validurl1b, "unmodified url1 after failure arg2");
is_deeply($validurl2, $validurl2b, "unmodified url2 after failure arg2");

ok(CAF::Download::URL::_merge_url($validurl1, $validurl2, 1),
   "can merge url1 and url12 with update");

# do the merge by hand
$validurl1b->{filename} = $validurl2b->{filename};
$validurl1b->{x509} = {%{$validurl2b->{x509}}};

is_deeply($validurl1, $validurl1b, "modified url1 with correct value after merge");
is_deeply($validurl2, $validurl2b, "unmodified url2 after merge");

# going to merge url2 with url1c, without update
ok($validurl2->{filename} ne $validurl1c->{filename},
   "url1c and url2 have different filename");
ok(CAF::Download::URL::_merge_url($validurl2, $validurl1c, 0),
   "can merge url1c and url12 with update");

# do the merge by hand
# do not copy the filename, should be untouched with update=0
$validurl2b->{krb5} = {%{$validurl1c->{krb5}}};
$validurl2b->{server} = 'myserver';

is_deeply($validurl2, $validurl2b, "url2 merged without update");

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
                    $res->{server} = $server;
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


=pod

=item parse_urls

=cut

$d->{fail} = undef;

# 2 valid urls, one string, one hashref
my $current_defaults = set_url_defaults();
my $url1 = {server => 'server1', filename => '/location1', proto => 'https'};
my $url2_orig = {server => 'server2', filename => '/location2', proto => 'http'};
my $url2 = {};
ok(CAF::Download::URL::_merge_url($url2, $url2_orig, 1), "Made a copy of url2_orig");
ok(CAF::Download::URL::_merge_url($url1, $current_defaults, 0), "merged url1 with current defaults");
ok(CAF::Download::URL::_merge_url($url2, $current_defaults, 0), "merged url2 with current defaults");

is_deeply($d->parse_urls(["https://server1/location1", $url2_orig]),
          [$url1, $url2],
          "parsed one stringurl and one hashurl");

ok(! defined($d->parse_urls([[qw(a b)]])), "parse_urls fails, url is either a string or a hashref");
is($d->{fail}, 'Url has wrong type ARRAY.', "parse_urls fails with correct message");

ok(! defined($d->parse_urls(["invalid://string"])), "Url string needs to be valid string");
is($d->{fail}, 'Invalid auth+method+protocol for invalid', "parse_urls fails with correct message");

ok(! defined($d->parse_urls([{x => 1}])), "Url hashref needs to be valid url");
is($d->{fail}, 'Cannot parse invalid url hashref.', "parse_urls fails with correct message");


=pod

=back

=cut

done_testing();
