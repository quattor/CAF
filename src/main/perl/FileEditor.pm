# ${license-info}
# ${developer-info
# ${author-info}
# ${build-info}
#
package CAF::FileEditor;

use strict;
use warnings;
use CAF::FileWriter;
use LC::File;

our @ISA = qw (CAF::FileWriter);

sub new
{
    my $class = shift;
    my $self = $class->SUPER::new (@_);
    my $txt = LC::File::file_contents (*$self->{filename});
    $self->IO::String::open ($txt);
}

sub open
{
    return new(@_);
}
