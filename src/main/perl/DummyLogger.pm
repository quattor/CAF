# ${license-info}
# ${developer-info
# ${author-info}
# ${build-info}
#

package CAF::DummyLogger;

use strict;
use warnings;

=pod

=head1 NAME

CAF::DummyLogger - Class for mocking a Log4Perl logger 

=head1 SYNOPSIS

    use CAF::DummyLogger;

    my $log = CAF::DummyLogger->new();
    $log->error("whatever");

=head1 DESCRIPTION

Use a CAF::DumyLogger instance as fallback logger in CAF when no 
logger instance was passed, to simplify CAF code.

=cut

sub new {
    my $that = shift;
    my $proto = ref($that) || $that;
    my $self = { @_ };
    bless($self, $proto);
    return $self;
}

# Mock basic methods of Log4Perl getLogger instance
no strict 'refs';
foreach my $i (qw(error warn info verbose debug)) {
    *{$i} = sub {}
}
use strict 'refs';

1;
