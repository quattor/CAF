use strict;
use warnings;

use Test::More;
use Test::MockModule;
use Test::Quattor::Object;
use LC::Exception qw(throw_error);
use CAF::Object;

use FindBin qw($Bin);
use lib "$Bin/modules";

use exception_helper;

my $mockobj = Test::MockModule->new('CAF::Object');


=pod

=head1 SYNOPSIS

Test all methods for C<CAF::Exception>

=head2 dummy object test package

=cut

{
    package test_caf_exception;
    use parent qw(CAF::Object CAF::Exception);
    #our $EC = LC::Exception::Context->new->will_store_all;
    sub _initialize ## no critic (Subroutines::ProhibitNestedSubs)
    {
        my ($self, %opts) = @_;
        foreach my $optname (qw(log NoAction)) {
            $self->{$optname} = $opts{$optname} if exists $opts{$optname};
        };
        return CAF::Object::SUCCESS;
    };
}

# the exception context of this unittest
my $EC = LC::Exception::Context->new->will_store_all;

# Because we throw an error below from this unittest (ie main package)
# we must have a exception context EC that we can use to reset it
# So setting up and following the EC from the temporary package will not help us
# Normally you don't do things this way, and stuff should be ok.
# There's a support group for people who do not understand LC::Exception
# They're called everyone, they meet at the bar (apologies to GCarlin)
# for convenience
#my $ec = $test_caf_exception::EC;
my $ec = $EC;

# set the EC in the helper module
set_ec_check($ec);

my $ec_check = set_ec_check();
is($ec_check, $ec, "tets_caf_object EC set in helper");


my $logobj = Test::Quattor::Object->new();
my $tco = test_caf_exception->new(log => $logobj);

=head2 _get_noaction

=cut

ok(!defined $tco->noAction(), "noAction method returns undef");

# return defined value (none set during init)
$mockobj->mock('noAction', sub {return 1});

$CAF::Object::NoAction = 0;

ok($tco->_get_noaction(), "_get_noaction returns false with noAction=1 CAF::Object::NoAction=0 and no keeps_state");
ok($tco->_get_noaction(0), "_get_noaction returns false with noAction=1 CAF::Object::NoAction=0 and keeps_state false");
ok(! $tco->_get_noaction(1), "_get_noaction returns false with noAction=1 CAF::Object::NoAction=0 and keeps_state true");

$CAF::Object::NoAction = 1;

ok($tco->_get_noaction(), "_get_noaction returns true with noAction=1 CAF::Object::NoAction=1 and no keeps_state");
ok($tco->_get_noaction(0), "_get_noaction returns true with noAction=1 CAF::Object::NoAction=1 and keeps_state false");
ok(! $tco->_get_noaction(1), "_get_noaction returns false with noAction=1 CAF::Object::NoAction=1 and keeps_state true");

# use original noAction method which returns undef (so global CAF::Object::NoAction is used instead)
$mockobj->unmock('noAction');

$CAF::Object::NoAction = 0;

ok(! $tco->_get_noaction(), "_get_noaction returns false with CAF::Object::NoAction=0 and no keeps_state");
ok(! $tco->_get_noaction(0), "_get_noaction returns false with CAF::Object::NoAction=0 and keeps_state false");
ok(! $tco->_get_noaction(1), "_get_noaction returns false with CAF::Object::NoAction=0 and keeps_state true");

$CAF::Object::NoAction = 1;

ok($tco->_get_noaction(), "_get_noaction returns true with CAF::Object::NoAction=1 and no keeps_state");
ok($tco->_get_noaction(0), "_get_noaction returns true with CAF::Object::NoAction=1 and keeps_state false");
ok(! $tco->_get_noaction(1), "_get_noaction returns false with CAF::Object::NoAction=1 and keeps_state true");

=head2 _reset_exception_fail

=cut


init_exception($tco, "test _reset_exception_fail");

ok($tco->_reset_exception_fail(undef, $ec), "_reset_exception_fail returns SUCCESS");

# expected_reset is 0 here, because it's not mocked yet
verify_exception($tco, "test _reset_exception_fail", 0, 0);

# Continue with mocking _reset_exception_fail
mock_reset_exception_fail();

=head2 _function_catch

=cut

my $args = [];
my $opts = {};

my $success_func = sub {
    my ($arg1, $arg2, %opts) = @_;
    push(@$args, $arg1, $arg2);
    while (my ($k, $v) = each %opts) {
        $opts->{$k} = $v;
    };
    return 100;
};

# Empty args and opts refs
$args = [];
$opts = {};

init_exception($tco, "_function_catch success");

is($tco->_function_catch($success_func, [qw(a b)], {c => 'd', e => 'f'}, $ec), 100,
   "_function_catch with success_func returns correct value");
is_deeply($args, [qw(a b)], "_function_catch passes arg arrayref correctly");
is_deeply($opts, {c => 'd', e => 'f'}, "_function_catch passes opt hashref correctly");

verify_exception($tco, "_function_catch success");

# Test failures/exception
# Not going to check args/opts
my $failure_func = sub {
    throw_error('failure_func failed', 'no real reason');
    return 200;
};

init_exception($tco, "_function_catch fail");


ok(! defined($tco->_function_catch($failure_func, undef, undef, $ec)),
   "_function_catch with failure_func returns undef");

verify_exception($tco, "_function_catch fail", '\*\*\* failure_func failed: no real reason');

=head2 _safe_eval

=cut

my $funcref = sub {
    my ($ok, %opts) = @_;
    if ($ok) {
        return "hooray $opts{test}";
    } else {
        die "bad day today $opts{test}";
    }
};


my $verbose = [];
$mockobj->mock('verbose', sub {shift; push(@$verbose, \@_);});

init_exception($tco, "_safe_eval ok");

$verbose = [];
is($tco->_safe_eval($funcref, [1], {test => 123}, "eval fail", "eval ok", $ec), "hooray 123",
   "_safe_eval with non-die function returns returnvalue");
is_deeply($verbose, [['eval ok: ', 'hooray 123']], "_safe_eval reports result verbose");

init_exception($tco, "_safe_eval ok pt2");

$verbose = [];
$tco->{sensitive} = 1;
is($tco->_safe_eval($funcref, [1], {test => 123}, "eval fail", "eval ok", $ec), "hooray 123",
   "_safe_eval with non-die function returns returnvalue pt2");
is_deeply($verbose, [['eval ok: ', '<sensitive>']],
          "_safe_eval does not report result verbose with sensitive=1");

verify_exception($tco, "_safe_eval ok");

init_exception($tco, "_safe_eval fail");

ok(! defined($tco->_safe_eval($funcref, [0], {test => 123}, "eval fail", "eval ok", $ec)),
   "_safe_eval with die function returns undef");

verify_exception($tco, "_safe_eval fail", '^eval fail: bad day today 123');

=pod

=back

=cut

done_testing();
