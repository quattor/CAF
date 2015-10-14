package myservice;

use strict;
use warnings;

use CAF::Service qw(__make_method FLAVOURS);

our $AUTOLOAD;
use parent qw(CAF::Service);

sub _initialize {
    my ($self, %opts) = @_;
    return $self->SUPER::_initialize(['myservice'], %opts);
}

my $method = 'init';
foreach my $flavour (FLAVOURS) {
    no strict 'refs';
    *{"${method}_${flavour}"} = __make_method($method, $flavour);
    use strict 'refs';
}

1;
