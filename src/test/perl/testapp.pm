=pod

=head1 SYNOPSIS

Common CAF::Application for unit tests. It wraps the verbose method to
something more obvious, so that applications can check what has been
written.

=cut

package testapp;

use strict;
use warnings;
use CAF::Process;
use CAF::Application;


our @ISA = qw(CAF::Application);

sub verbose
{
    
    my ($self, @lines) = @_;
    my $text = join ("", @lines);
    my $fh = $CAF::Reporter::_REP_SETUP->{LOGFILE};
    print $fh $text;
}

1;
