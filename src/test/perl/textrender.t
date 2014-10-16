# -*- perl -*-
use strict;
use warnings;
use Test::More;
use Test::Quattor;
use CAF::TextRender;
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

my $mock = Test::MockModule->new('CAF::TextRender');
$mock->mock('error', sub {
   my $self = shift;
   $self->{ERROR}++;
   return 1;  
});


=pod

=head1 SYNOPSIS

Test all methods for C<CAF::TextRender>

=cut

my $contents = {
    'name_level0' => 'value_level0',
    'level1' => {
        'name_level1' => 'value_level1',
    }
};

my $trd;

$trd = CAF::TextRender->new('something', $contents);
isa_ok ($trd, "CAF::TextRender", "Correct class after new method");
ok(!defined($trd->warn('something')), "Fake logger initialised");

$trd = CAF::TextRender->new('not_a_reserved_module', $contents);
isa_ok ($trd, "CAF::TextRender", "Correct class after new method");
is(get_name($trd->{method}), "tt", "fallback/default render method tt selected");

is($trd->{includepath}, '/usr/share/templates/quattor', 'Default template base');
is($trd->{relpath}, 'metaconfig', 'Default template relpath');

$trd = CAF::TextRender->new('test', $contents,
                            includepath => getcwd()."/src/test/resources",
                            relpath => 'rendertest',
                            );
my $sane_tpl = $trd->sanitize_template();
is($sane_tpl, "rendertest/test.tt", "correct TT file with relpath prefixed");

my $tpl = CAF::TextRender::get_template_instance($trd->{includepath});
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
ok($tpl->process($sane_tpl, $contents, \$str, "Generation of test.tt")) or diag("Failed generation of test.tt TT error: " . $tpl->error(),
    "Test TT verified");
is($str, $res, "test.tt rendered contents correctly (test.tt is ok)");

=pod 

=head2 Test tt method

Test the CAF::TextRender tt call

=cut

is($trd->tt(), $res, "test.tt rendered contents correctly");


=pod

=head2 Test render text

Test rendering the text and stringification overload

=cut

is($trd->get_text(), $res, "stringification successful");
is("$trd", $res, "stringification overload successful");

=pod 

=head2 Test cache

Test the get_text caching by modifying the internal cache directly.

=cut

ok(exists($trd->{_cache}), "Cache exists");
is($trd->{_cache}, $res, "Latests result is cached");

my $modified = "NOCACHE";
# never ever do this in the code itself.
$trd->{_cache} = $modified;
is($trd->get_text(), $modified, "Cache is used (returning the content of _cache rather then the rendered text)");
is($trd->get_text(1), $res, "Cache is cleared (returning re-rendered text)");
is($trd->{_cache}, $res, "Latests result is cached again.");

my $nocachetrd = CAF::TextRender->new('test', $contents,
                                      includepath => getcwd()."/src/test/resources",
                                      relpath => 'rendertest',
                                      usecache => 0,
                                      );
isa_ok ($nocachetrd, "CAF::TextRender", "Correct class after new method (no cache)");
is($nocachetrd->get_text(), $res, "No cache rendering successful");
ok(! exists($nocachetrd->{_cache}), "No cache exists");

=pod

=head2 Test render failure

Test failing render (stringification returns undef).

=cut

ok(defined("$trd"), "render succes, stringification returns something defined");

my $brokentrd = CAF::TextRender->new('test_broken', $contents,
                                      includepath => getcwd()."/src/test/resources",
                                      relpath => 'rendertest',
                                      );
isa_ok ($brokentrd, "CAF::TextRender", "Correct class after new method (but with broken TT)");
ok(! defined($brokentrd->get_text()), "get_text returns undef, rendering failed");
is("$brokentrd", "", "render failed, stringification returns empty string");

=pod

=head2 Test invalid module

Test invalid module

=cut

my $invalidtrd = CAF::TextRender->new('invalid module;', $contents,
                                      includepath => getcwd()."/src/test/resources",
                                      relpath => 'rendertest',
                                      );
isa_ok ($invalidtrd, "CAF::TextRender", "Correct class after new method (but with invalid module)");
ok(! defined($invalidtrd->{method}), "invalid module result in undefined render method");
ok(! defined($invalidtrd->get_text()), "get_text returns undef with invalid module/undefined method");
is("$invalidtrd", "", "invalid module, stringification returns empty string");


=pod

=head2 Test filehandle

Test filehandle options

=cut

my $fh = $trd->filewriter("/some/name");
isa_ok($fh, "CAF::FileWriter", "CAF::TextRender fh method returns CAF::FileWriter");
is("$fh", $res, "File contents as expected");

my $header = "HEADER"; # no newline, check TODO
my $footer = "FOOTER"; # no newline, eol should add one
$fh = $trd->filewriter("/some/name",
               header => $header,
               footer => $footer,
               );
isa_ok($fh, "CAF::FileWriter", "CAF::TextRender fh method returns CAF::FileWriter");
# add newline due to eol
is("$fh", $header.$res.$footer."\n", "File contents as expected");

# test undef returned on render failure
ok(! defined($brokentrd->filewriter("/my/file")), "render failed, filewriter returns undef");


# force the internal module for testing purposes!
$trd->{module} = '/my/abs/path';
ok(!defined($trd->sanitize_template()), "module as template can't be absolute path");
$trd->{module} = 'nottest';
ok(!defined($trd->sanitize_template()), "no TT file nottest");

=pod

=head2 Test eol

Test end-of-line (eol)

=cut

$trd = CAF::TextRender->new('noeol', $contents,
                            includepath => getcwd()."/src/test/resources",
                            relpath => 'rendertest',
                            eol => 0,
                            );
my $noeol = "noeol";
is("$trd", $noeol, "noeol.tt rendered as expected");
unlike("$trd", qr{\n$}, "No newline at end of rendered text");

$trd = CAF::TextRender->new('noeol', $contents,
                            includepath => getcwd()."/src/test/resources",
                            relpath => 'rendertest',
                            );
is($trd->{eol}, 1, "eol default to true");
is("$trd", "$noeol\n", "noeol.tt with eol=1 rendered as expected");
like("$trd", qr{\n$}, "Newline at end of rendered text (with eol=1)");

=pod

=head2 Test load_module failures

Test load_module failures

=cut

$trd->{ERROR}=0;
ok(!$trd->load_module('foobarbaz'), "Invalid module loading fails");
ok($@, "Invalid module loading raises an exception");
is($trd->{ERROR}, 1, "Error was reported");


=pod

=head2 Reserved modules

Test the reserved modules

=head3 json

Test json/JSON::XS

=cut

$res = '{"level1":{"name_level1":"value_level1"},"name_level0":"value_level0"}';
$trd = CAF::TextRender->new('json', $contents, eol=>0);
ok($trd->load_module('JSON::XS'), "JSON::XS loaded");
is("$trd", $res, "json module rendered correctly");

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
$trd = CAF::TextRender->new('yaml', $contents);
ok($trd->load_module('YAML::XS'), "YAML::XS loaded");
is("$trd", $res, "yaml module rendered correctly");

=pod

=head3 properties

Test properties/Config::Properties

=cut

$res = <<EOF;

level1.name_level1=value_level1
name_level0=value_level0
EOF
$trd = CAF::TextRender->new('properties', $contents);
ok($trd->load_module('Config::Properties'), "Config::Properties loaded");
my ($line, @txt) = split("\n", "$trd");
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
$trd = CAF::TextRender->new('tiny', $contents);
ok($trd->load_module('Config::Tiny'), "Config::Tiny loaded");
is("$trd", $res, "tiny module rendered correctly");

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
$trd = CAF::TextRender->new('general', $contents);
ok($trd->load_module('Config::General'), "Config::General loaded");
is("$trd", $res, "general module rendered correctly");

done_testing();
