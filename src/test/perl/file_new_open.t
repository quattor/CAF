use strict;
use warnings;

BEGIN {
    # remove the module path that is holding the temp LC mock
    # we actually want to run something here
    @INC = grep { $_ !~ m/resources$/ } @INC;
}


use Test::More;
use Class::Inspector;

use CAF::FileWriter;
use CAF::FileEditor;
use CAF::FileReader;

use File::Path;
use File::Temp qw(tempfile);
use Test::Quattor::Object;

my $testdir = 'target/test/file_new_open';
mkpath($testdir);
# only a filename
my(undef, $filename) = tempfile(DIR => $testdir, OPEN=>0);

=pod

Test CAF::FileReader example: new with seek_begin, with self-reference so usable as e.g. <fh>.

=cut

open(FH, "> $filename");
print FH "line1\nline2\nline3\n";
close(FH);

# use open
my $fh = CAF::FileReader->open($filename);
is(join("X", <$fh>), "line1\nXline2\nXline3\n", "FileReader-open works as expected on filename $filename (incl seek_begin)");

=pod

This test verifies that the aliased opens from FileWriter/Editor/Reader
are aliases of their own classes, and not the parent ones.

=cut

foreach my $class (qw(Writer Editor Reader)) {
    my $fclass = "CAF::File$class";
    my $all_methods = Class::Inspector->methods($fclass, "expanded");
    diag "Handling $fclass";
    my $open = 'No::open::found';
    my ($open_ref, $new_ref);
    foreach my $method (@$all_methods) {
        # 3rd element is method name, 2nd is the class, 4th code ref (1st is joined)
        if ($method->[2] eq 'open') {
            diag explain "open ", $method;
            $open = $method->[1];
            $open_ref = $method->[3];
        } elsif ($method->[2] eq 'new') {
            diag explain "new ", $method;
            $new_ref = $method->[3];
        }
    }
    is($open, $fclass, "open is open from expected class $fclass (not parent)");
    ok($open_ref == $new_ref, "open and new code references from $fclass are equal");
}



done_testing;
