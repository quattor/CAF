package filetools;

use strict;
use warnings;

use parent qw(Exporter);
use File::Basename qw(dirname);
use File::Path qw(mkpath);

our @EXPORT_OK = qw(readfile makefile);

# cannot use mocked filewriter
sub makefile
{
    my $fn = shift;
    my $dir = dirname($fn);
    mkpath $dir if ! -d $dir;
    open(my $fh, '>', $fn) or die "filetools makefile failed to open $fn: $!";
    print $fh (shift || "ok");
    close($fh) or die "filetools makefile failed to close $fn: $!";
}

sub readfile
{
    my $fn = shift;
    open(my $fh, $fn) or die "filetools readfile failed to open $fn: $!";
    my $txt = join('', <$fh>);
    close($fh) or die "filetools readfile failed to close $fn: $!";

    return $txt;
}

1;
