use strict;
use warnings;
use Test::More;
use CAF::Application;
use Test::Quattor::Object;
use Readonly;

=pod

=head1 SYNOPSIS

Tests for the C<option> and C<option_exists> methods of C<CAF::Application>.

=cut

our $this_app = CAF::Application->new('option test');

Readonly my $OPTION1 => 'testopt';
Readonly my $OPTION_VAL1 => 'value1';
Readonly my $OPTION_VAL2 => 'value2';


# Check that option_exists() returns true if option exists and false otherwise
ok(!$this_app->option_exists($OPTION1), "Option $OPTION1 doesn't exist");
$this_app->set_option($OPTION1, $OPTION_VAL1);
ok($this_app->option_exists($OPTION1), "Option $OPTION1 defined");

# option() tests for an existing option
for my $expected_value ($OPTION_VAL1, $OPTION_VAL2) {
    $this_app->set_option($OPTION1, $expected_value);
    my $option_value = $this_app->option($OPTION1);
    is($option_value, $expected_value, "Option has expected value ($expected_value)");
}

# option() tests for an undefined option
ok(! defined($this_app->option('undefined_option')), "undef returned when option is undefined (no default value)");
is($this_app->option('undefined_option', $OPTION_VAL1), $OPTION_VAL1, "default value returned if option is undefined");
ok(! defined($this_app->option('undefined_option')), "option stays undefined after calling set_option with a default value");


done_testing();
