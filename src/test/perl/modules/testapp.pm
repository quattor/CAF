=pod

=head1 SYNOPSIS

Common CAF::Application for unit tests. It wraps the verbose method to
something more obvious, so that applications can check what has been
written.

=cut

package testapp;

use strict;
use warnings;
use Test::More;
use CAF::Process;
use CAF::Application;
use LC::Exception qw (SUCCESS);

use CAF::History;

our @ISA = qw(CAF::Application);

sub app_options {
    push(my @array, {
        NAME => 'logfile=s',
        HELP => 'log path/filename to use',
    });

    return \@array;
}

sub _initialize {
    my $self = shift;

    $self->{'LOG_TSTAMP'} = 1;
    $self->{'LOG_PROCID'} = 1;

    # start initialization of CAF::Application
    if($self->SUPER::_initialize(@_)) {
        # why is this not the default?
        $self->set_report_logfile($self->{'LOG'});
        return SUCCESS;
    }
    return;
}

sub verbose
{

    my ($self, @lines) = @_;
    my $text = join ("", @lines);
    my $fh = $CAF::Reporter::_REP_SETUP->{LOGFILE};
    print $fh $text if defined($fh);
    diag "[VERB] $text\n";
}

sub debug
{
    my ($self, $lvl, @lines) = @_;
    my $text = join ("", @lines);
    diag "[DEBUG] $lvl $text\n";
}



1;
