package myobjecttext;

use strict;
use warnings;

use parent qw(CAF::ObjectText);

# simplistic subclass to unittest CAF::ObjectText

sub _initialize
{
    my ($self, $text, $test, %opts) = @_;

    %opts = () if !%opts;

    # sets e.g. $self->{log}
    $self->_initialize_textopts(%opts);

    $self->{text} = $text;
    $self->{test} = $test;

    $self->{opt} = $opts{opt};

    return 1;
}

sub _get_text_test
{
    my $self = shift;
    return $self->{test} ? 1 : $self->fail('_get_text_test false');
}

sub _get_text
{
    my $self = shift;
    return ($self->{text}, '_get_text errormsg');
}

1;
