# -*- perl -*-
use strict;
use warnings;
use Test::More;
use Test::Quattor;
use CAF::Render;
use Test::MockModule;

use B qw(svref_2object);

# http://stackoverflow.com/questions/7419071/determining-the-subroutine-name-of-a-perl-code-reference
sub get_name {
    my $sub_ref = shift;
    my $cv = svref_2object ( $sub_ref );
    my $gv = $cv->GV;
    return $gv->NAME;
}

=pod

=head1 SYNOPSIS

Test all methods for C<CAF::Render>

=cut

my $contents = {
    'name_level0' => 'value_level0',
    'level1' => {
        'name_level1' => 'value_level1',
    }
};

my $rnd;

$rnd = CAF::Render->new('something', $contents);
isa_ok ($rnd, "CAF::Render", "Correct class after new method");
ok(!defined($rnd->{log}->error('something')), "Fake logger initialised");

$rnd = CAF::Render->new('not_a_reserved_module', $contents);
isa_ok ($rnd, "CAF::Render", "Correct class after new method");
is(get_name($rnd->{method}), "tt", "fallback/default render method tt selected");


done_testing();
