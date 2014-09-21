# -*- perl -*-
use strict;
use warnings;
use Test::More;
use Test::Quattor;
use CAF::Render;
use Test::MockModule;
use Cwd;

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

is($rnd->{templatebase}, '/usr/share/templates/quattor', 'Default template base');
is($rnd->{relpath}, 'metaconfig', 'Default template relpath');

$rnd = CAF::Render->new('test', $contents,
                        templatebase => getcwd()."/src/test/resources",
                        relpath => 'rendertest',
                        );
is($rnd->sanitize_template(), "rendertest/test.tt", "correct TT file with relpath prefixed");

# force the internal module for testing purposes!
$rnd->{module} = '/my/abs/path';
ok(!defined($rnd->sanitize_template()), "module as template can't be absolute path");
$rnd->{module} = 'nottest';
ok(!defined($rnd->sanitize_template()), "no TT file nottest");


done_testing();
