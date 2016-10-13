use strict;
use warnings;

use Test::More;
use Test::Quattor;
use CAF::Kerberos;
use Test::MockModule;
use GSSAPI;
use Test::Quattor::Object;
use Cwd;
use CAF::Object qw(SUCCESS);

$CAF::Object::NoAction = 1;

my $obj = Test::Quattor::Object->new();

my $tmppath;
my $mock = Test::MockModule->new("CAF::Kerberos");
$mock->mock('tempdir', sub { mkdir($tmppath); return $tmppath; });

# copy
my $orig_env = { %ENV };

# Currently missing:
# get_context
# get_name
# _spnego_iflags
# _gss_decrypt

=pod

=head1 SYNOPSIS

Test all methods for C<CAF::Kerberos>

=over

=item _initialize

=cut

my $def_srv_keytab = '/etc/krb5.keytab';
my $init_p_str = 'service1/inst1/inst2@REALM';
my $init_principal = {
    primary => 'service1',
    instances => [qw(inst1 inst2)],
    realm => 'REALM',
};

my $krb = CAF::Kerberos->new(
    log => $obj,
    lifetime => 100,
    principal => $init_p_str,
    );
isa_ok($krb, 'CAF::Kerberos', 'returns a CAF::Kerberos instance');

is_deeply($krb->{ticket}, {
    lifetime => 100,
    keytab => $def_srv_keytab,
    }, 'ticket lifetime and default server keytab set during init');

is_deeply($krb->{principal}, $init_principal, 'principal set via principal string');

is_deeply($krb->{ENV}, {
    KRB5_KTNAME => $def_srv_keytab,
    KRB5_CLIENT_KTNAME => $def_srv_keytab,
    }, 'ENV hashref with default server keytab created');

=item update_ticket_options

=cut

my $keytab1 = '/some/path';

$krb->update_ticket_options(lifetime => 10, keytab => $keytab1);

is_deeply($krb->{ticket}, {
    lifetime => 10,
    keytab => $keytab1,
    }, 'ticket lifetime and keytab updated');
is_deeply($krb->{ENV}, {
    KRB5_KTNAME => $keytab1,
    KRB5_CLIENT_KTNAME => $keytab1,
    }, 'ENV hashref with updated keytab created');

=item _principal_string / _split_principal_string

=cut

# Test split, incl failure
is_deeply($krb->_split_principal_string($init_p_str), $init_principal,
          'principal string splitted as expected');
ok(! defined($krb->_split_principal_string('a@b@c')),
   '_split_principal_string returns undef in case of more than one realm separator');
ok(! defined($krb->_split_principal_string('/b@c')),
   '_split_principal_string returns undef in case of empty primary');


# Test generation, incl failure
ok(! defined($krb->_principal_string({'noprimary' => 'woohoo'})),
   '_principal_string returns undef if no primary is set');
ok(! defined($krb->_principal_string({'primary' => '()woohoo'})),
   '_principal_string returns undef if primary has invalid characters');
ok(! defined($krb->_principal_string({'primary' => 'woohoo', instances => ["valid", "invalid()"]})),
   '_principal_string returns undef if one of the instances has invalid characters');
ok(! defined($krb->_principal_string({'primary' => 'woohoo', realm => 'realm()'})),
   '_principal_string returns undef if realm has invalid characters');
is($krb->_principal_string({'primary' => 'p', 'instances' => [qw(i0 i1)], 'realm' => 'realm'}),
   'p/i0/i1@realm', 'Correct principal string generated from provided hashref');
is($krb->_principal_string(),
   $init_p_str, 'Correct principal string generated from instance');


=item update_principal

=cut

# Test undef
is_deeply($krb->{principal}, $init_principal, 'principal set via principal string (pre-update)');
ok(! defined($krb->update_principal(principal => 'a@b@c')),
   'update_principal failed with invalid principal');
ok(! defined($krb->update_principal(instances => 'myinstances')),
   'update_principal failed with invalid instances (must be arrayref)');
is_deeply($krb->{principal}, $init_principal, 'principal unmodified with update_principal error');

# This does modify the current attributes, all valid ones are changed
ok(! defined($krb->update_principal(principal => 'a/()b@c')),
   'update_principal failed with principal with valid structure but with invalid characters');

# Test update
$krb->update_principal(primary => 'newprim', instances => [qw(i0 i1)], realm => 'r1');
is_deeply($krb->{principal}, {
    primary => 'newprim',
    instances => [qw(i0 i1)],
    realm => 'r1',
    }, 'principal updated via primary/instances/realm');

$krb->update_principal(principal => 'p/a/b@c');
is_deeply($krb->{principal}, {
    primary => 'p',
    instances => [qw(a b)],
    realm => 'c',
    }, 'principal updated via principal');

# Test preferences
$krb->update_principal(principal => 'p2/a2/b2@c2', 'primary' => 'p3');
is_deeply($krb->{principal}, {
    primary => 'p3',
    instances => [qw(a2 b2)],
    realm => 'c2',
    }, 'principal updated via principal and primary (primary precedes principal string)');

# _process is tested in kerberos-process

=item _kinit

=cut

command_history_reset();
my $cmdline = '/usr/bin/kinit -l 10 -k -t /some/path p3/a2/b2@c2';
ok($krb->_kinit(), '_kinit successful');
my $proc = get_command($cmdline);
isa_ok($proc->{object}, 'CAF::Process', 'kinit process called as expected');

# fail
command_history_reset();
set_command_status($cmdline, 1);
ok(! defined($krb->_kinit()), '_kinit fails and returns undef');
$proc = get_command($cmdline);
isa_ok($proc->{object}, 'CAF::Process', 'kinit process called as expected (but failed)');

# destroy instance, hold $krb as log, will prevent DESTROY test at the end
$proc->{object} = undef;
$proc = undef;

=item create_credential_cache

=cut

my $kinit;

$tmppath = "target/cc_dir";
$mock->mock('_kinit', sub {my $self = shift; $kinit = 1; return $self->fail("kinit failed");});
$kinit = undef;
ok(! defined($krb->create_credential_cache()), 'create_credential_cache returns undef on kinit failure');
ok($kinit, "_kinit called");
is($krb->{fail}, 'Failed to get TGT for credential cache target/cc_dir: kinit failed',
   "create_credential_cache sets fail attribute on kinit failure");
is($krb->{ccdir}, $tmppath, 'expected credential cache directory on kinit fialure');
is($krb->{ENV}->{KRB5CCNAME}, "FILE:$tmppath/tkt",
   'define credential cache FILE as tkt in directory KRB5CCNAME on kinit failure');


# success
$mock->mock('_kinit', sub {$kinit = 1; return 1;});
$kinit = undef;
ok($krb->create_credential_cache(), 'create_credential_cache returns success');
ok($kinit, "_kinit called");
is($krb->{ccdir}, $tmppath, 'expected credential cache directory');
is($krb->{ENV}->{KRB5CCNAME}, "FILE:$tmppath/tkt",
   'define credential cache FILE as tkt in directory KRB5CCNAME');



=item _gss_status

=cut

# ok status from name instance via manual  Name->import
my ($manual_name_instance, $manual_name_instance2);
my $status = GSSAPI::Name->import($manual_name_instance, 'server@realm', GSSAPI::OID::gss_nt_krb5_name);
isa_ok($manual_name_instance, 'GSSAPI::Name', 'manual_name_instance is a GSSAPI::Name instance');

is($krb->get_hrname($manual_name_instance), 'server@realm', 'name instance created with expected hrname');

$krb->{fail} = '';
isa_ok($status, 'GSSAPI::Status', 'status is a GSSAPI::Status instance');
ok($status, "manual_name_instance status is ok"); # GSSAPI::Status has overloaded bool
is($krb->_gss_status($status), SUCCESS, '_gss_status converts ok status in SUCCESS');
is($krb->{fail}, '', 'fail attribute not changed on success');

# failed status using GSSAPI::Name compare that fails due to undef 2nd name
$krb->{fail} = '';
my $status2b; # is actually also status2, but lets not go into details too much
my $status2 = $manual_name_instance->compare(undef, $status2b);
ok(! $status2, 'manual_name_instance->compare status2 is false');
ok(! defined($krb->_gss_status($status2, text => 'some text')), '_gss_status returns undef on failure');
like($krb->{fail}, qr{^GSS Error some text: MAJOR: A required input .*? MINOR: .*}, 'fail attribute set on failure');

# handcrafted status
# GSS major error determines success if it is bitshifted
# (major is 32bit, offset 16 (routine error) and 24 (caling error) are real errors)
$krb->{fail} = '';
my $status3 = GSSAPI::Status->new(1, 0);
ok($status3, 'manual status3 is ok');
ok($krb->_gss_status($status3, text => 'some other3 text'), '_gss_status returns SUCCESS');
is($krb->{fail}, '', 'fail attribute not set on SUCCESS');

$krb->{fail} = '';
my $status4 = GSSAPI::Status->new(1 + 2 <<16, 0);
ok(! $status2, 'manual status4 is false');
ok(! defined($krb->_gss_status($status4, text => 'some other4 text')), '_gss_status returns undef on failure');
like($krb->{fail}, qr{^GSS Error some other4 text: MAJOR: .*? MINOR: .*}, 'fail attribute set on failure');

=item _gssapi_ wrappers

=cut

my $gssapi_wrappers = \%CAF::Kerberos::GSSAPI_INTERFACE_WRAPPER;
is_deeply($gssapi_wrappers, {
    Context => [qw(accept init valid_time_left wrap unwrap)],
    Name => [qw(display import)],
    Cred => [qw(acquire_cred inquire_cred)],
    }, 'GSSAPI_INTERFACE_WRAPPER');

# The somewhat strange GSSAPI::Name->import
# This test tests the strange-looking '$self = shift;' code
my $name_instance;
$krb->{fail} = '';
ok($krb->_gssapi_import($name_instance, 'server@realm', GSSAPI::OID::gss_nt_krb5_name),
   '_gssapi_import is used to create a GSSAPI::Name instance and returns success');
isa_ok($name_instance, 'GSSAPI::Name', 'is a GSSAPI::Name instance');

my @fnames;
foreach my $class (sort keys %$gssapi_wrappers) {
    foreach my $method (@{$gssapi_wrappers->{$class}}) {
        # reset fail attribute
        $krb->{fail} = '';
        my $fname = "_gssapi_$method";
        my $fclass = join('::', 'GSSAPI', $class);
        my $fmethod = join('::', $fclass, $method);

        # Test that there are no doubles (e.g. same method name in Context and Name)
        is(scalar (grep {$_ eq $fname} @fnames), 0, "$fname is unique method name");
        push(@fnames, $fname);

        # only testing failures, very hard to mock the XS stuff
        ok($krb->can($fname), "$fname method exists");

        my ($a, $b, $c) = qw(a b c);
        if ($method ne 'display') {
            # There's something very strange display
            # perl -e 'use GSSAPI;eval {GSSAPI::Name::display->(1,2,3,4,5)};print "end $@\n"'
            #    Not enough arguments for GSSAPI::Name::display at -e line 1, near "GSSAPI::Name::display->"
            #    Execution of -e aborted due to compilation errors.
            # eval{} does not catch this. Is this some bug in the XS?
            $krb->{fail} = '';
            ok(! defined($krb->$fname($a, $b, $c)), "$fname returns undef in of croak");
            my $err_regexp = "^$fname $fmethod croaked:";
            like($krb->{fail}, qr{$err_regexp}, "$fname fails with croaked message when incorrect args are passed");
        }

        $krb->{fail} = '';
        $a = {};
        ok(! defined($krb->$fname($a, $b, $c)), "$fname returns undef in case of instance mismatch");
        my $expected_class = $method eq 'acquire_cred' ? 'GSSAPI::Name' : $fclass;
        my $err_regexp = "^$fname expected a $expected_class instance, got ref";
        like($krb->{fail}, qr{$err_regexp}, "$fname fails with instance mismatch");
    }
}

=item DESTROY

=cut

ok(-d $tmppath, "ccache tmppath $tmppath exists");
$krb = undef;
ok(! -d $tmppath, "ccache tmppath $tmppath does not exist anymore after DESTROY");

=item check env

=cut

is_deeply({ %ENV }, $orig_env, 'unmodified environment after all testing');


done_testing();
