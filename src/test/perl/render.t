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
my $sane_tpl = $rnd->sanitize_template();
is($sane_tpl, "rendertest/test.tt", "correct TT file with relpath prefixed");
my $tpl = $rnd->get_template_instance(); 
isa_ok ($tpl, "Template", "Returns Template instance");

my $res = <<EOF;
L0 value_level0
L1 name_level1 VALUE value_level1
EOF

# test the unittest test.tt (if this test fails, the test itself is broken)
my $str;
if(!$tpl->process($sane_tpl, $contents, \$str)) {;
    diag("Failed generation of test.tt with ".$tpl->error);
};
is($str, $res, "test.tt rendered contents correctly (test.tt is ok)");

# now test the CAF::Render tt call
is($rnd->tt(), $res, "test.tt rendered contents correctly");

# test stringification overload
is($rnd->get_text(), $res, "stringification successful");
is("$rnd", $res, "stringification overload successful");

# test filehandle options
my $fh = $rnd->fh("/some/name");
isa_ok($fh, "CAF::FileWriter", "CAF::Render fh method returns CAF::FileWriter");
is("$fh", $res, "File contents as expected");


# force the internal module for testing purposes!
$rnd->{module} = '/my/abs/path';
ok(!defined($rnd->sanitize_template()), "module as template can't be absolute path");
$rnd->{module} = 'nottest';
ok(!defined($rnd->sanitize_template()), "no TT file nottest");


done_testing();