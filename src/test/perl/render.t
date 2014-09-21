# -*- perl -*-
use strict;
use warnings;
use Test::More;
use Test::Quattor;
use CAF::Render;
use Test::MockModule;

=pod

=head1 SYNOPSIS

Test all methods for C<CAF::Render>

=cut

my $data = {
    'name_level0' => 'value_level0',
    'level1' => {
        'name_level1' => 'value_level1',
    }
};

my $rnd = CAF::Render->new('tiny', $data);
isa_ok ($rnd, "CAF::Render", "Correct class after new method");


done_testing();
