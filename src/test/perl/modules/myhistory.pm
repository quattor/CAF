package myhistory;

use strict;
use warnings;
use LC::Exception qw (SUCCESS);

use parent qw(CAF::Object CAF::History);

sub _initialize
{
    my ($self, $history, $keep) = @_;
    $self->init_history($keep) if $history;
    return SUCCESS;
};

sub do_something
{
    my $self = shift;
    $self->event($self, something => 'done');
}

1;
