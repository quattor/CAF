package myhistory;

use strict;
use warnings;
use LC::Exception qw (SUCCESS);
use CAF::History;

use parent qw(CAF::Object);

# Example integration
# For actual usage, look at CAF:: Reporter

use Readonly;
Readonly my $HISTORY => 'HISTORY';

sub _initialize
{
    my ($self, $history, $keep) = @_;
    $self->{$HISTORY} = CAF::History->new($keep) if $history;
    return SUCCESS;
};

sub event
{
    my ($self, $obj, %metadata) = @_;
    return SUCCESS if(! defined($self->{$HISTORY}));
    $metadata{whoami} = ref($self);
    $self->{$HISTORY}->event($obj, %metadata);
}

1;
