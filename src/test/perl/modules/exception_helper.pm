package exception_helper;

use strict;
use warnings;

use Test::MockModule;
use Test::More;

use parent qw(Exporter);

our @EXPORT = qw(init_exception verify_exception mock_reset_exception_fail set_ec_check);

my $mock = Test::MockModule->new('CAF::Exception');

our $exception_reset = 0;
our $symlink_call_count = 0;
our $hardlink_call_count = 0;
our $function_catch_call_count = 0;

my $ec_check;


# Set LC exception instance if arg is defined; return ec_check
sub set_ec_check
{
    my $ec = shift;
    $ec_check = $ec if defined($ec);

    return $ec_check;
}

# init_exception() and verify_exception() functions work in pair. They allow to register a message
# in 'fail' attribute at the beginning of a test section and to verify if new (unexpected) exceptions
# where raised during the test section. To reset the 'fail' attribute after verify_exception(),
# call _reset_exception_fail(). init_exception() implicitely resets the 'fail' attribute and also
# reset to 0 the count of calls to _reset_exception_fail().
sub init_exception
{
    my ($tco, $msg) = @_;
    $exception_reset = 0;
    $symlink_call_count = 0;
    $hardlink_call_count = 0;
    $function_catch_call_count = 0;

    # Set the fail attribute, it should be reset
    $tco->{fail} = "origfailure $msg";

    # Inject an error, _function_catch should handle it gracefully (i.e. ignore it)
    my $myerror = LC::Exception->new();
    $myerror->reason("origexception $msg");
    $myerror->is_error(1);
    $ec_check->error($myerror);

    ok($ec_check->error(), "Error before $msg");
}

sub verify_exception
{
    my ($tco, $msg, $fail, $expected_reset, $noreset) = @_;
    $expected_reset = 1 if (! defined($expected_reset));
    is($exception_reset, $expected_reset, "_reset_exception_fail called $expected_reset times after $msg");
    if ($noreset) {
        ok($ec_check->error(), "Error not reset after $msg");
    } else {
        ok(! $ec_check->error(), "Error reset after $msg");
    };
    if ($noreset && defined($tco->{fail})) {
        like($tco->{fail}, qr{^origfailure }, "Fail attribute matches originalfailure on noreset after $msg");
    } elsif ($fail && defined($tco->{fail})) {
        like($tco->{fail}, qr{$fail}, "Fail attribute matches $fail after $msg");
        unlike($tco->{fail}, qr{origfailure}, "original fail attribute reset");
    } elsif ( ! $noreset ) {
        ok(! defined($tco->{fail}), "Fail attribute reset after $msg");
    } else {
        ok(0, "internal test error: unexpected undefined fail attribute") if (! defined($tco->{fail}));
    };
};


sub mock_reset_exception_fail
{
    $mock->mock('_reset_exception_fail', sub {
        $exception_reset += 1;
        diag "mocked _reset_exception_fail $exception_reset times ".(scalar @_ >= 2 && defined($_[1]) ? $_[1] : '');
        my $init = $mock->original("_reset_exception_fail");
        return &$init(@_);
    });
}

1;
