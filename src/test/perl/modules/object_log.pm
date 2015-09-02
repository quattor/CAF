package object_log;

use strict;
use warnings;
use LC::Exception qw (SUCCESS);

use parent qw(CAF::Object);

sub _initialize {
    # set noaction
    my ($self, $logger) = @_;
    $self->{log} = $logger;
    return SUCCESS; 
};

1;
