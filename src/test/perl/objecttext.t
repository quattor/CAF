use strict;
use warnings;
use Test::More;
use Test::Quattor;
use Test::Quattor::Object;
use Test::MockModule;

use FindBin qw($Bin);
use lib "$Bin/modules";
use myobjecttext;

my $mock = Test::MockModule->new('CAF::ObjectText');

=pod

=head1 SYNOPSIS

Test all methods for C<CAF::ObjectText>

=item _initialize_textopts

=cut

my $TEXT = "text";
my $TEXTEOL = "$TEXT\n";

my $obj = Test::Quattor::Object->new();

my $ot = myobjecttext->new($TEXT, 1);
isa_ok($ot, 'myobjecttext', 'ot is a myobjecttext instance');
isa_ok($ot, 'CAF::ObjectText', 'a myobjecttext instance is also a CAF::ObjectText instance');
isa_ok($ot, 'CAF::Object', 'a myobjecttext instance is also a CAF::Object instance');

ok(! defined($ot->{log}), 'no log attribute set by default');
ok($ot->{eol}, 'eol attribute set to true by default');
ok($ot->{usecache}, 'usecache attribute set to true by default');

my $optot = myobjecttext->new($TEXT, 1, log => $obj, eol => 0, usecache => 0);
isa_ok($optot, 'myobjecttext', 'optot is a myobjecttext instance');
isa_ok($optot->{log}, 'Test::Quattor::Object', 'log attribute set via _initialize_textopts');
ok(! $optot->{eol}, 'eol attribute set to false via _initialize_textopts');
ok(! $optot->{usecache}, 'usecache attribute set to false via _initialize_textopts');

=head2 fail

=cut

my $verbose;
$mock->mock('verbose', sub {shift; $verbose = \@_;});

my $failot = myobjecttext->new();
isa_ok($failot, 'myobjecttext', 'failot is a myobjecttext instance');

my @failmsg = qw(something went really wrong);
ok(! defined($failot->fail(@failmsg)), 'fail returns undef');
is($failot->{fail}, join('', @failmsg), 'fail sets fail atrribute with joined arguments');
is_deeply($verbose, ['FAIL: ', $failot->{fail}], 'fail logs verbose with FAIL prefix');

=head2 Test _get_text_test=true

=cut

is([$ot->_get_text()]->[0], $TEXT, "_get_text produces expected text with ot");
ok($ot->_get_text_test(), '_get_text_test returns true with ot');
is($ot->get_text(), $TEXTEOL, 'get_text returns expected text with ot');
is("$ot", $TEXTEOL, "stringification produces expected text with ot");
my $fh = $ot->filewriter('/some/path');
isa_ok($fh, 'CAF::FileWriter', "filewriter returns CAF::FileWriter instance with ot");
$fh->close();

=head2 eol with get_text

=cut

ok($ot->{eol}, 'eol enabled for ot');
is([$ot->_get_text()]->[0], $TEXT, "_get_text produces non-eol text with ot");
ok($ot->_get_text_test(), '_get_text_test returns true with ot');
is($ot->get_text(), $TEXTEOL, 'get_text returns eol text with ot');
is("$ot", $TEXTEOL, "stringification produces eol text with ot");

ok(! $optot->{eol}, 'eol disabled for optot');
is([$optot->_get_text()]->[0], $TEXT, "_get_text produces non-eol text with optot");
ok($optot->_get_text_test(), '_get_text_test returns true with optot');
is($optot->get_text(), $TEXT, 'get_text returns non-el text with optot');
is("$optot", $TEXT, "stringification produces non-eol text with optot");


=head2 Test _get_text_test=false

=cut

my $brokenot = myobjecttext->new($TEXT, 0);
isa_ok($brokenot, 'myobjecttext', 'brokenot is a myobjecttext instance');
is([$brokenot->_get_text()]->[0], $TEXT, "_get_text produces expected text with brokenot");
ok(! $brokenot->_get_text_test(), '_get_text_test returns false with brokenot');
ok(! defined($brokenot->get_text()), 'get_text returns undef with brokenot');
is("$brokenot", "", "stringification produces empty string with brokenot");
ok(! defined($brokenot->filewriter('/some/path')), "filewriter returns undef with brokenot");

=head2 Test failing _get_text

=cut

my $brokenot2 = myobjecttext->new(undef, 1);
isa_ok($brokenot2, 'myobjecttext', 'brokenot2 is a myobjecttext instance');
ok(! defined([$brokenot2->_get_text()]->[0]), "_get_text produces undef as first element with brokenot2");
is([$brokenot2->_get_text()]->[1], '_get_text errormsg',
   "_get_text has error message as 2nd element with brokenot2");
ok($brokenot2->_get_text_test(), '_get_text_test returns true with brokenot2');

ok(! defined($brokenot2->get_text()), 'get_text returns undef with brokenot2');
is($brokenot2->{fail}, '_get_text errormsg', 'failing _get_text causes get_text to set fail attribute');
is("$brokenot2", "", "stringification produces empty string with brokenot2");
ok(! defined($brokenot2->filewriter('/some/path')), "filewriter returns undef with brokenot2");

$brokenot2->{fail} = 'somefailure';
ok(! defined($brokenot2->get_text()), 'get_text returns undef with brokenot2');
is($brokenot2->{fail}, '_get_text errormsg: somefailure',
   'failing _get_text causes get_text to set fail attribute appending previous fail message');


=pod

=head2 Test cache

Test the get_text caching by modifying the internal cache directly.

=cut

is($ot->get_text(), $TEXTEOL, 'get_text produces correct text');

ok(exists($ot->{_cache}), "Cache exists");
is($ot->{_cache}, $TEXTEOL, "Latests result is cached");

my $MODIFIED = "NOCACHE\n";
# never ever do this in the code itself.
$ot->{_cache} = $MODIFIED;
is($ot->get_text(), $MODIFIED, "Cache is used (returning the content of _cache rather than the produced text)");
is($ot->get_text(1), $TEXTEOL, "Cache is cleared (returning re-produced text)");
is($ot->{_cache}, $TEXTEOL, "Latests result is cached again.");
is($ot->get_text(), $TEXTEOL, "Cache is used (returning the content of _cache rather than the produced text)");

my $nocacheot = myobjecttext->new($TEXTEOL, 1,usecache => 0);
isa_ok ($nocacheot, "myobjecttext", "Correct class after new method (no cache)");
is($nocacheot->get_text(), $TEXTEOL, "No cache rendering successful");
ok(! exists($nocacheot->{_cache}), "No cache exists");

=pod

=head2 Test filehandle

Test filehandle options

=cut

$fh = $ot->filewriter("/some/name");
isa_ok($fh, "CAF::FileWriter", "CAF::ObjectText filewriter method returns CAF::FileWriter");
is("$fh", $TEXTEOL, "File contents as expected");

my $header = "HEADER"; # no newline, eol should add one
my $footer = "FOOTER"; # no newline, eol should add one
$fh = $ot->filewriter("/some/name",
               header => $header,
               footer => $footer,
               );
isa_ok($fh, "CAF::FileWriter", "CAF::ObjectText filewriter method returns CAF::FileWriter");
# add newline due to eol to header, footer and text
is("$fh", $header."\n".$TEXTEOL.$footer."\n", "File contents as expected with header and footer (and eol)");


done_testing();
