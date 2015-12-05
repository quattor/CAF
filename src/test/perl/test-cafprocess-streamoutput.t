#!/usr/bin/perl

BEGIN {
    # remove the module path that is holding the temp LC mock
    # we actually want to run something here
    @INC = grep { $_ !~ m/resources$/ } @INC;
}

use FindBin qw($Bin);
# actually running executable; don't fake LC
use lib "$Bin/modules";

use strict;
use warnings;
use testapp;
use CAF::Process;
use Test::More;
use Cwd 'abs_path';

my $exe = abs_path("$Bin/../resources/stream_output.sh");

my ($fh, $str, $output);

open ($fh, ">", \$str);
my $this_app = testapp->new ($0, qw (--verbose));
$this_app->set_report_logfile ($fh);

my $string_output='';

sub string_output_function {
    my ($newout) = @_;
    $string_output .= $newout;
}

my $p = CAF::Process->new ([$exe]);
$output = $p->stream_output(\&string_output_function);

# validate output
#BEGIN
#BEGIN_remainderSEQ 1
#SEQ_1_remainderSEQ 2
#SEQ_2_remainderSEQ 3
#SEQ_3_remainderEND
#END_remainder
like($output, qr{^BEGIN$}m, "Found BEGIN");
like($output, qr{^BEGIN_remainderSEQ 1$}m, "Found BEGIN remainder / SEQ 1");
like($output, qr{^SEQ_1_remainderSEQ 2$}m, "Found SEQ 1 remainder / SEQ 2");
like($output, qr{^SEQ_2_remainderSEQ 3$}m, "Found SEQ 2 remainder / SEQ 3");
like($output, qr{^SEQ_3_remainderEND$}m, "Found SEQ 3 remainder / END");
like($output, qr{^END_remainder$}m, "Found END remainder");

is($string_output, $output, "The gathered otput via the string_output_function is the same as the returned output");

my @lines = ();
my $nr_lines_call = 0;

sub lines_function  {
    my ($arg1, $arg2, $new) = @_;
    push(@lines,$new) if ($arg1 eq "1st" && $arg2 eq "2nd"); 
    $nr_lines_call++;
}

my $lines_output = $p->stream_output(\&lines_function, mode => 'line',arguments => [qw (1st 2nd)]);
is($lines_output, $output, "The returned output via the lines_function is the same as the normal output");

is(scalar @lines, 6, "6 lines of output (one)");
is(scalar @lines, $nr_lines_call, "one lines_function call perl line");

done_testing();
