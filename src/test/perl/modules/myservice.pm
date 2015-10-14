package myservice;

use strict;
use warnings;

use Test::More;

use CAF::Service qw(__make_method FLAVOURS);

our $AUTOLOAD;
use parent qw(CAF::Service);

sub _initialize {
    my ($self, %opts) = @_;
    return $self->SUPER::_initialize(['myservice'], %opts);
}

# subclass new autoloaded magic
my $method = 'init';
foreach my $flavour (FLAVOURS) {
    no strict 'refs';
    *{"${method}_${flavour}"} = __make_method($method, $flavour);
    use strict 'refs';
}

# subclass existing autloaded method
sub stop
{
    my ($self, @args) = @_;

    diag 'myservice stop called';
    $self->{mystop} = 1;

    return $self->SUPER::stop(@args);
}

1;
