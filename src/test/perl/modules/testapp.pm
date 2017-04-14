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
use CAF::FileWriter;

our $EC = LC::Exception::Context->new()->will_store_errors();

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
    if ($self->SUPER::_initialize(@_)) {
        # why is this not the default?
        $self->config_reporter(logfile => $self->{'LOG'});
        return SUCCESS;
    }
    return;
}

sub verbose
{

    my ($self, @lines) = @_;
    my $text = join ("", @lines);
    my $fh = $CAF::Reporter::_REP_SETUP->{LOGFILE};
    print $fh "$text\n" if defined($fh);
    diag "[VERB] $text\n";
}

sub debug
{
    my ($self, $lvl, @lines) = @_;
    my $text = join ("", @lines);
    diag "[DEBUG] $lvl $text\n";
}

# Test old-style error throwing/catching
sub err_mkfile
{
    my ($self, $filename, $txt) = @_;
    my $fh = CAF::FileWriter->new($filename);
    print $fh $txt;
    $fh->close();

    my $ret;
    if ($EC->error()) {
        $ret = $EC->error->text;
        $EC->ignore_error;
    }
    return $ret
}

1;
