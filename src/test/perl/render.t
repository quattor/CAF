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

is($rnd->{includepath}, '/usr/share/templates/quattor', 'Default template base');
is($rnd->{relpath}, 'metaconfig', 'Default template relpath');

$rnd = CAF::Render->new('test', $contents,
                        includepath => getcwd()."/src/test/resources",
                        relpath => 'rendertest',
                        );
my $sane_tpl = $rnd->sanitize_template();
is($sane_tpl, "rendertest/test.tt", "correct TT file with relpath prefixed");

my $tpl = CAF::Render::get_template_instance($rnd->{includepath});
isa_ok ($tpl, "Template", "Returns Template instance");

my $res;
$res = <<EOF;
L0 value_level0
L1 name_level1 VALUE value_level1
EOF

=pod

=head2 Validate the test.tt itself

Test the unittest test.tt (if this test fails, the test itself is broken)

=cut

my $str;
ok($tpl->process($sane_tpl, $contents, \$str, "Generation of test.tt")) or diag("Failed generation of test.tt TT error: " . $tpl->error());
is($str, $res, "test.tt rendered contents correctly (test.tt is ok)");

=pod 

=head2 Test tt method

Test the CAF::Render tt call

=cut

is($rnd->tt(), $res, "test.tt rendered contents correctly");


=pod

=head2 Test render text

Test rendering the text and stringification overload

=cut

is($rnd->get_text(), $res, "stringification successful");
is("$rnd", $res, "stringification overload successful");


=pod

=head2 Test filehandle

Test filehandle options

=cut

my $fh = $rnd->fh("/some/name");
isa_ok($fh, "CAF::FileWriter", "CAF::Render fh method returns CAF::FileWriter");
is("$fh", $res, "File contents as expected");


# force the internal module for testing purposes!
$rnd->{module} = '/my/abs/path';
ok(!defined($rnd->sanitize_template()), "module as template can't be absolute path");
$rnd->{module} = 'nottest';
ok(!defined($rnd->sanitize_template()), "no TT file nottest");


=pod

=head2 Reserved modules

Test the reserved modules

=head3 json

Test json/JSON::XS

=cut

$res = '{"level1":{"name_level1":"value_level1"},"name_level0":"value_level0"}';
$rnd = CAF::Render->new('json', $contents);
ok($rnd->load_module('JSON::XS'), "JSON::XS loaded");
is("$rnd", $res, "json module rendered correctly");

=pod

=head3 yaml

Test yaml/YAML::XS

=cut

$res = <<EOF;
---
level1:
  name_level1: value_level1
name_level0: value_level0
EOF
$rnd = CAF::Render->new('yaml', $contents);
ok($rnd->load_module('YAML::XS'), "YAML::XS loaded");
is("$rnd", $res, "yaml module rendered correctly");

=pod

=head3 properties

Test properties/Config::Properties

=cut

$res = <<EOF;

level1.name_level1=value_level1
name_level0=value_level0
EOF
$rnd = CAF::Render->new('properties', $contents);
ok($rnd->load_module('Config::Properties'), "Config::Properties loaded");
my ($line, @txt) = split("\n", "$rnd");
# first line is a header with timestamp.
like($line, qr{^#\s.*$}, "Start with header (contains timestamp)");
# add extra newline
is(join("\n", @txt,''), $res, "properties module rendered correctly");

=pod

=head3 tiny

Test tiny/Config::Tiny

=cut

$res = <<EOF;
name_level0=value_level0

[level1]
name_level1=value_level1
EOF
$rnd = CAF::Render->new('tiny', $contents);
ok($rnd->load_module('Config::Tiny'), "Config::Tiny loaded");
is("$rnd", $res, "tiny module rendered correctly");

=pod

=head3 general

Test general/Config::General

=cut

$res = <<EOF;
<level1>
    name_level1   value_level1
</level1>
name_level0   value_level0
EOF
$rnd = CAF::Render->new('general', $contents);
ok($rnd->load_module('Config::General'), "Config::General loaded");
is("$rnd", $res, "general module rendered correctly");

done_testing();
