package object_noaction;

use strict;
use warnings;
use LC::Exception qw (SUCCESS);

use parent qw(CAF::Object);

sub _initialize {
    # set noaction
    my ($self, $noaction) = @_;
    $self->{NoAction} = $noaction;
    return SUCCESS; 
};

1;
