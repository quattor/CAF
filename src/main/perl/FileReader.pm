# ${license-info}
# ${developer-info
# ${author-info}
# ${build-info}


package CAF::FileReader;

use strict;
use warnings;
use base qw(CAF::FileEditor);
use Fcntl qw(:seek);

=pod

=head1 NAME

CAF::FileReader - Class for only reading files in CAF applications.

Normal use:

    use CAF::FileReader;
    my $fh = CAF::FileReader->open ("my/path");
    while (my $line = <$fh>) {
       # Do something
    }

=head1 DESCRIPTION

This class should be used whenever a file is to be opened for reading,
and no modifications are expected.

=cut

sub new
{
    my ($class, @opts) = @_;

    my $self = $class->SUPER::new(@opts);

    seek($self, 0, SEEK_SET);

    $self->cancel();
    return $self;
}

1;
