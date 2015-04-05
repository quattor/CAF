#!/usr/bin/perl
use strict;
use warnings;
use lib 'src/test/resources';
use testapp;
use CAF::FileEditor;
use Test::More;
use Carp qw(confess);
our $filename = `mktemp`;
use constant TEXT => <<EOF;
En un lugar de La Mancha, de cuyo nombre no quiero acordarme
no ha tiempo que vivía un hidalgo de los de lanza en astillero...
EOF
use constant HEADTEXT => <<EOF;
... adarga antigua, rocín flaco y galgo corredor.
EOF

chomp($filename);
our $text = TEXT;

our %opts = ();
our $path;
my ($log, $str);
my $this_app = testapp->new ($0, qw (--verbose));

$SIG{__DIE__} = \&confess;

*testapp::error = sub {
    my $self = shift;
    $self->{ERROR} = @_;
};

open ($log, ">", \$str);
my $fh = CAF::FileEditor->new ($filename);
isa_ok ($fh, "CAF::FileEditor", "Correct class after new method");
isa_ok ($fh, "CAF::FileWriter", "Correct class inheritance after new method");
is (${$fh->string_ref()}, TEXT, "File opened and correctly read");
$fh->close();

is(*$fh->{filename}, $filename, "The object stores its parent's attributes");

is ($opts{contents}, TEXT, "Attempted to write the file with the correct contents");
$fh = CAF::FileEditor->open ($filename);
$fh->head_print (HEADTEXT);
is (${$fh->string_ref()}, HEADTEXT . TEXT,
    "head_print method working properly");
isa_ok ($fh, "CAF::FileEditor", "Correct class after open method");
isa_ok ($fh, "CAF::FileWriter", "Correct class inheritance after open method");
$fh->close();
$fh = CAF::FileEditor->open($filename);
print $fh HEADTEXT;
is(${$fh->string_ref()}, TEXT.HEADTEXT,
   "print method working as expected");

$fh->replace_lines(qr(This line doesn't exist), qr(This.*exist),
		   "This line does exist");
unlike(${$fh->string_ref()}, qr(This line does exist),
       "replace_lines doesn't do anything if no matches");
$fh->replace_lines(HEADTEXT, ".*corredor",
		   "no corredor");
unlike(${$fh->string_ref()}, qr(no corredor),
       "replace_lines doesn't do anything if the good regexp exists");
my $re = "There was Eru, who in Arda is called Ilúvatar" . HEADTEXT;
$fh->replace_lines(HEADTEXT, "There was Eru.*", $re);
like(${$fh->string_ref()},  qr($re),
     "replace lines actually replaces lines that match re but not goodre");
$fh = CAF::FileEditor->new($filename);
print $fh TEXT;
$fh->add_or_replace_lines(qr(En un lugar de La Mancha), qr(En un lugar de La Mancha),
		    "This is a new content", BEGINNING_OF_FILE);
unlike(${$fh->string_ref()}, qr(This is a new content),
       "add_or_replace doesn't add anything if there are matches");
$fh->add_or_replace_lines("En un lugar de La Mancha", "There was Eru",
			  "There was Eru En un lugar de La Mancha",
			  ENDING_OF_FILE);
like(${$fh->string_ref()},
     qr(There was Eru En un lugar de La Mancha),
     "add_or_replace replaces correctly");
unlike(${$fh->string_ref()},
       qr(^En un lugar de La Mancha"),
       "add_or_replace actually has replaced and not added anything");
$fh->add_or_replace_lines(qr(Arda), qr(Eru),
			  qq(There was Eru, the One, who in Arda is called Ilúvatar\n),
			  BEGINNING_OF_FILE);
like(${$fh->string_ref()},
     qr(^There was Eru, the One),
     "add_or_replace adds lines to the beginning if needed");
$fh->add_or_replace_lines("Ainur", "Ones",
			  "\nand he made first the Ainur, the Holy Ones",
			 ENDING_OF_FILE);
like(${$fh->string_ref()},
     qr(the Holy Ones$),
     "add_or_replace adds lines to the end, if needed");

$fh->add_or_replace_lines("fubar", "baz", "fubarbaz", 3.14);
unlike($fh, qr{fubar}, "Invalid whence does nothing");

$fh->replace_lines(qr(la mancha)i, qr(blah blah blah), "la mancha blah blah blah");
like(${$fh->string_ref()},
     qr(la mancha blah blah blah)s,
     "Regular expression modifiers work");

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

close ($log);
open ($log, ">", \$str);
$this_app->set_report_logfile($log);
$fh = CAF::FileEditor->new($filename, log => $this_app);
$fh->add_or_replace_lines("ljhljh", "Ljhljhluih", "oiojhpih",
			  BEGINNING_OF_FILE);
ok($str, "Debug output invoked by add_or_replace_lines when there is a log object");
close ($log);
open ($log, ">", \$str);
$this_app->set_report_logfile($log);
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
