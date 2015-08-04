# -*- perl -*-
use strict;
use warnings;
use Test::More;
use Test::Quattor;
use CAF::TextRender qw($YAML_BOOL $YAML_BOOL_PREFIX);
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

is_deeply(CAF::TextRender::_convert_includepaths(),
          [qw(/usr/share/templates/quattor)],
          "convert_includepaths returns default includepaths with undef");
is_deeply(CAF::TextRender::_convert_includepaths('/a/b/c:/d/e/f'),
          [qw(/a/b/c /d/e/f)],
          "convert_includepaths returns ':'-splitted list with string argument");
is_deeply(CAF::TextRender::_convert_includepaths([qw(/a/b/c /d/e/f)]),
          [qw(/a/b/c /d/e/f)],
          "convert_includepaths returns arrayref list with arrayref argument");
ok(!defined(CAF::TextRender::_convert_includepaths({a => 'b', c => 'd'})),
   "convert_includepaths returns undef if args is none of the above");


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

# default relpath
$trd = CAF::TextRender->new('not_a_reserved_module', $contents);
isa_ok ($trd, "CAF::TextRender", "Correct class after new method");
is(get_name($trd->{method}), "tt", "fallback/default render method tt selected");
ok($trd->{method_is_tt},
   "method_is_tt set for fallback/default render method tt selected");
is_deeply($trd->{includepath}, ['/usr/share/templates/quattor'], 'Default template base');
is($trd->{relpath}, 'metaconfig', 'Default template relpath');

# empty relpath
$trd = CAF::TextRender->new('not_a_reserved_module',
                            $contents,
                            relpath => "",
                            );
isa_ok ($trd, "CAF::TextRender", "Correct class after new method");
is(get_name($trd->{method}), "tt", "fallback/default render method tt selected");
is($trd->{relpath}, '', 'empty template relpath');

$trd = CAF::TextRender->new('test', $contents,
                            includepath => getcwd()."/src/test/resources",
                            relpath => 'rendertest',
                            );
is($trd->{relpath}, 'rendertest', 'found rendertest template relpath');
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

=head2 Test mutiple includepaths

=cut

# tests usage of _convert_includepaths
my $tplm = CAF::TextRender::get_template_instance("/a:/b");
isa_ok ($tplm, "Template", "Returns Template instance");
# ugly!
is_deeply($tplm->{SERVICE}->{CONTEXT}->{CONFIG}->{INCLUDE_PATH},
          [qw(/a /b)],
          "multiple includepaths as expected");

my $trdm = CAF::TextRender->new('main', {test => "TEST", othertest => "OTHERTEST"},
                            includepath => [
                                "/does/not/exist",
                                getcwd()."/src/test/resources/rendertest/path2",
                                getcwd()."/src/test/resources/rendertest/path1",
                                ],
                            relpath => '', # emptyrelpath
                            );
is("$trdm", "TEST\nOTHERTEST\n\n", "rendering with multiple includepaths");

=pod

=head2 Validate the test.tt itself

Test the unittest test.tt (if this test fails, the test itself is broken)

=cut

my $str;
ok($tpl->process($sane_tpl, $contents, \$str), "Generation of test.tt") or diag("Failed generation of test.tt TT error: " . $tpl->error(),
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

=head2 Test TT default STRICT and RECURSION options

Test default STRICT  = 0 and RECURSION = 1 settings

=cut

my $defttoptstrd = CAF::TextRender->new('default_opts', { data => 'level0', recursion => { data => 'level1' }},
                                        includepath => getcwd()."/src/test/resources",
                                        relpath => 'rendertest',
                                        );
isa_ok ($defttoptstrd, "CAF::TextRender", "Correct class after new method (default tt options)");
is("$defttoptstrd", "level1\nlevel0\n", "Template rendered (no fail due to STRICT) and RECURSION supported correctly");
ok(! $defttoptstrd->{fail}, "No error is reported");


=head2 Test TT options

Test passing TT options such as CONSTANTS via the ttoptions hash-ref

=cut

my $ttoptstrd = CAF::TextRender->new('const', {},
                                      includepath => getcwd()."/src/test/resources",
                                      relpath => 'rendertest',
                                      ttoptions => { CONSTANTS => { magic => 'magic' } }
                                      );
isa_ok ($ttoptstrd, "CAF::TextRender", "Correct class after new method (tt options; empty contents)");
is("$ttoptstrd", "magic\n", "Template rendered constants correctly");

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
like($brokentrd->{fail}, qr{Failed to render with module .*: Unable to process template for file }, "Error is reported");


# not cached
ok(!exists($brokentrd->{_cache}), "Render failed, no caching of the event. (Failure will be recreated)");

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

my $header = "HEADER"; # no newline, eol should add one
my $footer = "FOOTER"; # no newline, eol should add one
$fh = $trd->filewriter("/some/name",
               header => $header,
               footer => $footer,
               );
isa_ok($fh, "CAF::FileWriter", "CAF::TextRender fh method returns CAF::FileWriter");
# add newline due to eol
is("$fh", $header."\n".$res.$footer."\n", "File contents as expected");

# test undef returned on render failure
ok(! defined($brokentrd->filewriter("/my/file")), "render failed, filewriter returns undef");

=pod

=head2 Successful executions

=cut


=head2 Test sanitize_template

Test that a template specified by Template::Toolkit is an existing
file in the metaconfig template directory.

It's here where the security of the module (and all its users) is
dealt with. After this, the component is allowed to trust all its
inputs.

=cut

# force the internal module for testing purposes!

$trd->{module} = "test.tt";
is($trd->sanitize_template(), "rendertest/test.tt",
   "Valid template is accepted");

$trd->{module} = "test";
is($trd->sanitize_template(), "rendertest/test.tt",
   "Valid template may have an extension added to it");


=pod

=over 5

=item * Absolute paths must be rejected

Otherwise, we might leak files like /etc/shadow or private keys.

=cut

$trd->{module} = '/my/abs/path';
ok(! defined($trd->sanitize_template()), "Absolute paths are rejected");
like($trd->{fail}, qr{Must have a relative template name}, "Error is reported");

=pod

=item * Non-existing files must be rejected

They may abuse File::Spec.

=cut

$trd->{module} = 'lhljkhljhlh789gg';
ok(!defined($trd->sanitize_template()), "Non-existing filenames are rejected");
like($trd->{fail}, qr{Non-existing template name}, "Non-existing templates are rejected, error logged");

=pod

=item * Templates must end up under C<<includepath>/<relpath>>

Templates in this component are jailed to that directory, again to
prevent cross-directory traversals.

=cut

# file has to exist (and has to be a file), otherwise it doesn't reach the jail regexp
$trd->{module} = '../unreachable.tt';

my $fn = $trd->{includepath}->[0] . "/$trd->{relpath}/$trd->{module}";
ok(-f $fn, "File $fn has to exist for test to make sense");

ok(!$trd->sanitize_template(),
   "It's not possible to leave the 'include/relpath' jail");
like($trd->{fail}, qr{Insecure template name.*Final template must be under}, "TT files have live under 'includepath/relpath', error logged");

=pod

=item * Fail with undefined includepath

When the includepath is undef (e.g. when initialised with neither one of
string, arrayref or undef), fail.

=back

=cut

$trd->{includepath} = undef;
ok(!$trd->sanitize_template(),
   "It's not possible to have undef includepath");
like($trd->{fail}, qr{^No includepath defined.$}, "includepath cannot be undef, error logged");

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

ok(!$trd->load_module('foobarbaz'), "Invalid module loading fails");
ok($@, "Invalid module loading raises an exception");
like($trd->{fail}, qr{Unable to load foobarbaz}, "Unable to load error was reported");


=pod

=head2 Test contents failure

=cut

my $brokencont = CAF::TextRender->new('yaml', [qw(array_ref)]);
isa_ok ($brokencont, "CAF::TextRender", "Correct class after new method (but with broken contents)");
ok(! defined($brokencont->get_text()), "get_text returns undef, contents failed");
is("$brokencont", "", "render failed, stringification returns empty string");
like($brokencont->{fail},
     qr{Contents is not a hashref \(ref ARRAY\)},
     "Error is reported");

# not cached
ok(!exists($brokencont->{_cache}),
   "Render failed, no caching of the event. (Failure will be recreated)");

=pod

=head2 Reserved modules

Test the reserved modules

=head3 json

Test json/JSON::XS

=cut

$res = '{"level1":{"name_level1":"value_level1"},"name_level0":"value_level0"}';
$trd = CAF::TextRender->new('json', $contents, eol=>0);
ok($trd->load_module('JSON::XS'), "JSON::XS loaded");
ok(! $trd->{method_is_tt}, "method_is_tt false for json");
is("$trd", $res, "json module rendered correctly");

# true/false tests
$trd = CAF::TextRender->new('json', {'yes' => \1, 'no' => \0}, eol=>0);
is("$trd", '{"no":false,"yes":true}',
   "json module renders booleans true/false correctly");

# test scalars
# use a hashref here, make_contents only allows for hashrefs in CAF::TextRender
$trd = CAF::TextRender->new('json', {a => "string" });
# overwrite the contents (to support subclassing like CCM::TextRender)
$trd->{contents} = "string";
ok(! defined($trd->get_text()),
   "Rendering scalar with JSON fails");
is($trd->{fail},
   "Failed to render with module json: contents for JSON rendering must be hash or array reference (got '' instead)",
   "Rendering scalar with JSON fails with expected message");

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
ok(! $trd->{method_is_tt}, "method_is_tt false for yaml");
is("$trd", $res, "yaml module rendered correctly");


# true/false tests
$trd = CAF::TextRender->new('yaml', $YAML_BOOL, eol=>0);
my $txt = "$trd";
$txt =~ s/\s//g;
is($txt, '---no:falseyes:true',
   "yaml module renders booleans true/false correctly");

# but this goes wrong
$trd = CAF::TextRender->new('yaml',
                            {'yes' => $YAML_BOOL->{'yes'}, 'no' => $YAML_BOOL->{'no'}},
                            eol=>0);
$txt = "$trd";
$txt =~ s/\s//g;
is("$txt", "---no:''yes:1",
   "yaml module renders booleans true/false incorrect when constructing hashref");

# so use the CAF::TextRender prefixing
$trd = CAF::TextRender->new('yaml',
                            {'yes' => $YAML_BOOL_PREFIX."true", 'no' =>   $YAML_BOOL_PREFIX."false"},
                            eol=>0);
$txt = "$trd";
$txt =~ s/\s//g;
is("$txt", '---no:falseyes:true',
   "yaml module renders booleans true/false correctly when using prefixing");


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
ok(! $trd->{method_is_tt}, "method_is_tt false for properties");
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
ok(! $trd->{method_is_tt}, "method_is_tt false for tiny");
is("$trd", $res, "tiny module rendered correctly");

=pod

=head3 general

Test general/Config::General

Warning: try to avoid due to reproducability issues

=cut

$trd = CAF::TextRender->new('general', $contents);
ok(! $trd->{method_is_tt}, "method_is_tt false for general");
ok($trd->load_module('Config::General'), "Config::General loaded");

# can't use full output, because it's not reproducable accross perl versions
like("$trd", qr{<level1>\n    name_level1   value_level1\n</level1>\n}, "general module rendered level1 correctly");
like("$trd", qr{name_level0   value_level0\n}, "general module rendered level0 correctly");

# No error logging in the module
ok(! exists($trd->{ERROR}), "No errors logged anywhere");


done_testing();
