#!/usr/bin/perl
use strict;
use warnings;

use Test::More;
$SIG{__WARN__} = sub {ok(0, "Perl warning: $_[0]");};

use FindBin qw($Bin);
use lib "$Bin/modules";

use testapp;
use CAF::FileEditor;

use Carp qw(confess);
use File::Path qw(mkpath);
use File::Temp qw(tempfile);
use CAF::Object;

use Test::MockModule;
my $mockapp = Test::MockModule->new('CAF::Application');
$mockapp->mock('error', sub {
    my ($self, @lines) = @_;
    $self->{ERROR} = @lines;
    my $text = join ("", @lines);
    diag "[ERROR] $text\n";
});

use Test::Quattor::Object;

my $obj = Test::Quattor::Object->new();

my $testdir = 'target/test/editor';
mkpath($testdir);
(undef, our $filename) = tempfile(DIR => $testdir);

use constant TEXT => <<EOF;
sysconfig = "in spanish"
En un lugar de La Mancha, de cuyo nombre no quiero acordarme
no ha tiempo que vivía un hidalgo de los de lanza en astillero...
EOF

use constant HEADTEXT => <<'EOF';
... adarga antigua, rocín flaco y galgo corredor.
EOF

chomp($filename);
# Mock existing file contents for resources/LC::File
our $text = TEXT;

# $path and %opts are set via the dummy resources/File::AtomicWrite module
# in resources/LC
our $path;
our %opts = ();

my $log;
my $str = '';
open ($log, ">", \$str);

sub init_test
{
    $path = "";
    %opts = ();
    close($log);
    $str = '';
    open ($log, ">", \$str);
}

my $this_app = testapp->new ($0, qw (--verbose --debug 5));

$SIG{__DIE__} = \&confess;

init_test();
my $fh = CAF::FileEditor->new ($filename,
    log => $obj,
);
isa_ok ($fh, "CAF::FileEditor", "Correct class after new method 1");
isa_ok ($fh, "CAF::FileWriter", "Correct class inheritance after new method 1");
is ("$fh", TEXT, "File opened and correctly read 1");
$fh->close();

# Nothing changed, no write
is(scalar keys %opts, 0, "Editor new/close does not do anything");


init_test();
$fh = CAF::FileEditor->new ($filename,
    backup => '.old',
    owner => 100,
    group => 200,
    mode => 0123,
    mtime => 1234567,
    log => $obj,
);
is ("$fh", TEXT, "File opened and correctly read 2");
print $fh "another line\n";
$fh->close();

diag "new opts ", explain \%opts;
# delete input, a ref to TEXT
delete $opts{input};
is_deeply(\%opts, {
    backup => '.old',
    owner => "100:200",
    mode => 0123,
    mtime => 1234567,
    contents => TEXT."another line\n",
    file => $filename,
    MKPATH => 1,
}, "options set in new() and current contents are passed to File::AtomicWrite");

is(*$fh->{filename}, $filename, "The object stores its parent's attributes");
is($opts{contents}, TEXT."another line\n", "Attempted to write the file with the correct contents");


$CAF::Object::NoAction = 1;
init_test();
$fh = CAF::FileEditor->open ($filename, keeps_state => 1);
$fh->head_print (HEADTEXT);
is ("$fh", HEADTEXT . TEXT, "head_print method working properly");
isa_ok ($fh, "CAF::FileEditor", "Correct class after open method");
isa_ok ($fh, "CAF::FileWriter", "Correct class inheritance after open method");
$fh->close();
diag "keeps_state + noaction=1 ", explain \%opts;
is_deeply([sort keys %opts], [qw(MKPATH contents file input)], "noaction=1 with keeps_state calls File::AtomicWrite::write_file");


$fh = CAF::FileEditor->open($filename);
print $fh HEADTEXT;
is("$fh", TEXT.HEADTEXT, "print method working as expected");

$fh->replace_lines(qr(This line doesn't exist), qr(This.*exist), "This line does exist");
unlike("$fh", qr(This line does exist), "replace_lines doesn't do anything if no matches");
$fh->replace_lines(HEADTEXT, ".*corredor", "no corredor");
unlike("$fh", qr(no corredor), "replace_lines doesn't do anything if the good regexp exists");

my $re = "There was Eru, who in Arda is called Ilúvatar" . HEADTEXT;
$fh->replace_lines(HEADTEXT, "There was Eru.*", $re);
$fh = CAF::FileEditor->new($filename, log => $this_app);
print $fh TEXT;
$fh->add_or_replace_lines(
    qr(En un lugar de La Mancha),
    qr(En un lugar de La Mancha),
    "This is a new content",
    BEGINNING_OF_FILE);
unlike("$fh", qr(This is a new content),
       "add_or_replace doesn't add anything if there are matches");
$fh->add_or_replace_lines(
    "En un lugar de La Mancha",
    "There was Eru",
    "There was Eru En un lugar de La Mancha",
    ENDING_OF_FILE);
like("$fh", qr(There was Eru En un lugar de La Mancha),
     "add_or_replace replaces correctly");
unlike("$fh", qr(^En un lugar de La Mancha"),
       "add_or_replace actually has replaced and not added anything");
$fh->add_or_replace_lines(
    qr(Arda),
    qr(Eru),
    qq(There was Eru, the One, who in Arda is called Ilúvatar\n),
    BEGINNING_OF_FILE);
like("$fh", qr(^There was Eru, the One),
     "add_or_replace adds lines to the beginning if needed");
$fh->add_or_replace_lines(
    "Ainur",
    "Ones",
    "\nand he made first the Ainur, the Holy Ones",
    ENDING_OF_FILE);
like("$fh", qr(the Holy Ones$),
     "add_or_replace adds lines to the end, if needed");

$fh->add_or_replace_lines("fubar", "baz", "fubarbaz", 3.14);
unlike($fh, qr{fubar}, "Invalid whence does nothing");

$fh->replace_lines(qr(la mancha)i, qr(blah blah blah), "la mancha blah blah blah");
like("$fh", qr(la mancha blah blah blah)s,
     "Regular expression modifiers work");

like($fh, qr{^sysconfig.*spanish}m,
     "add_or_replace_sysconfig_lines going to replace original sysconfig format entry");
$fh->add_or_replace_sysconfig_lines('sysconfig', "another language");
like($fh, qr{sysconfig=another language}m,
     "add_or_replace_sysconfig_lines replaces sysconfig format");
unlike($fh, qr{^sysconfig.*spanish}m,
     "add_or_replace_sysconfig_lines replaced original sysconfig format entry");

$fh->add_or_replace_sysconfig_lines("Quijote", "Rocinante");
like($fh, qr{Quijote\s*=\s*Rocinante$},
     "add_or_replace_sysconfig_lines adds the key to the end of the file by default");
$fh->add_or_replace_sysconfig_lines("Dulcinea", "Aldonza", BEGINNING_OF_FILE);
like($fh, qr{^Dulcinea\s*=\s*Aldonza},
     "Beginning of file honored in sysconfig lines");

$fh->remove_lines("Dulcinea", "Quijote");
unlike($fh, qr{Dulcinea}, "Correct line is removed");
$fh->remove_lines("Quijote", "Rocinante");
like($fh, qr{Quijote.*Rocinante}, "Line that matches good re is not removed");
$fh->cancel();

init_test();
$this_app->config_reporter(logfile => $log);

$fh = CAF::FileEditor->new($filename, log => $this_app);
$fh->add_or_replace_lines("ljhljh", "Ljhljhluih", "oiojhpih", BEGINNING_OF_FILE);
ok($str, "Debug output invoked by add_or_replace_lines when there is a log object");

init_test();
$this_app->config_reporter(logfile => $log);

$fh = CAF::FileEditor->new($filename, log => $this_app);
$fh->remove_lines("ljhljh", "lkjhljh");
ok($str, "Debug output invoked by remove_lines when there is a log object");

$this_app->{ERROR} = undef;
$fh->add_or_replace_lines("foo", "bar", "fubarbaz", 3.14);
ok($this_app->{ERROR}, "Invalid whence is logged");

$fh = CAF::FileEditor->new("ljhljhluhoh");
$str = $fh->string_ref();
ok(!$str || !$$str, "Empty buffer when the file doesn't exist");

done_testing();
