# ${license-info}
# ${developer-info}
# ${author-info}
# ${build-info}

package CAF::ReporterMany;

use strict;
use LC::Exception qw (SUCCESS throw_error);
use Sys::Syslog qw (openlog closelog);
use CAF::Reporter;
our @ISA;

=pod

=head1 NAME

CAF::ReporterMany - Class for console & log message reporting in CAF applications,
which allows more than one object instance

=head1 SYNOPSIS

    package myclass;
    use CAF::ReporterMany;
    use CAF::Log;
    @ISA = qw(CAF::ReporterMany);
    ...

    $logger = CAF::Log->new('/path/to/logfile', 'at');

    $self->setup_reporter(2, 0, 1);
    $self->set_report_logfile($logger);

    sub foo {
        my ($self,$a,$b,$c)=@_;
        ...
        $self->report("foo is doing well");
        $self->verbose("foo called with params $a $b $c");
        $self->debug(3,"foo is performing operation xyz");
        ...
    }

=head1 INHERITANCE

none.

=head1 DESCRIPTION

CAF::Reporter provides class methods for message (information,
warnings, error) reporting to standard output and a log file. There is
only one 'instance' of CAF::Reporter in an application. Classes
wanting to use CAF::Reporter have to inherit from it (using @ISA).

Usage of a log file is optional. A log file can be attached/detached
with the set_logfile method.


=cut


=pod

=head2 Public methods

=over 4

=item B<setup_reporter>(I<$debuglvl, $quiet, $verbose, $facility>): boolean

Reporter setup:

=over

=item I<$debuglvl>

sets the (highest) debug level, for messages reported with the B<debug> method.
The following recommendations apply:

    0: no debug information (default)
    1: main package
    2: main libraries/functions
    3: helper libraries
    4: core functions (constructors, destructors)

=item I<$quiet>

if set to a true value (e.g. 1), stop any output to console. Default is false

=item I<$verbose>

if set to a true value (e.g. 1), produce verbose output (via the B<verbose>
method). Default is false

=item I<$facility>

syslog facility the messages will be sent to. Default to local1

=back

If any of these arguments is C<undef>, current application settings
will be used.

=cut

sub setup_reporter($$$$$) {
    my ($self, $debuglvl, $quiet, $verbose,$facility) = @_;

    # pre-init
    while (my ($opt, $val) = each (%$CAF::Reporter::_REP_SETUP)) {
	$self->{$opt} = $val;
    }
    # reset the relevant ones
    $self->{'DEBUGLV'} = $debuglvl if (defined $debuglvl and $debuglvl > 0);
    $self->{'QUIET'} = 1 if $quiet;
    $self->{'VERBOSE'} = 1 if $verbose;
    $self->{'FACILITY'} = $facility unless !defined $facility;

    return SUCCESS;
}

=pod

=item B<set_report_logfile>(I<$logfile>): bool

If B<$logfile> is defined, it will be used as log file. $logfile can be any type
of class object reference, but the object must support a 'print(@array)'
method. Typically, it should be a L<CAF::Log> instance. If $logfile is
undefined (undef), no log file will be used.

=cut

sub set_report_logfile ($$) {
    my ($self, $logfile) = @_;

    $self->{'LOGFILE'} = $logfile;

    return SUCCESS;
}


=pod

=item B<report>(I<@array>): boolean

Report general information about the program progression. The output
to the console is supressed if 'quiet' is set. The strings in I<@array>
are concatenated and sent as a single line to the output(s).

=cut

sub report (@) {
    my $self = shift;

    my $string = join('',@_)."\n";
    print $string unless ($self->{'QUIET'});
    $self->log(@_);
    return SUCCESS;
}


=pod

=item B<info>(I<@array>): boolean

Report I<@array> using the B<report> method, but with an '[INFO]' prefix.

=cut

sub info (@) {
    my $self = shift;

    $self->syslog('info', @_);
    return $self->report('[INFO] ',@_);
}


=pod

=item B<OK>(I<@array>): boolean

Report I<@array> using the B<report> method, but with an '[OK]' prefix.

=cut

sub OK (@) {
    my $self = shift;

    $self->syslog('notice', @_);
    return $self->report('[OK]   ',@_);
}


=pod

=item B<warn>(I<@array>): boolean

Report I<@array> using the B<report> method, but with a '[WARN]' prefix.

=cut

sub warn (@) {
    my $self = shift;

    $self->syslog ('warning', @_);
    return $self->report('[WARN] ',@_);
}


=pod

=item B<error>(I<@array>): boolean

Report I<@array> using the B<report> method, but with an '[ERROR]' prefix.

=cut

sub error (@) {
    my $self = shift;

    $self->syslog ('err', @_);
    return $self->report('[ERROR] ',@_);
}


=pod

=item B<verbose>(I<@array>): boolean

Reports I<@array> using the B<report> method, but only if 'verbose' is set
to 1. Output is prefixed with '[VERB]'.

=cut

sub verbose (@) {
    my $self = shift;

    if ($self->{VERBOSE}) {
        $self->syslog ('notice', @_);
        return $self->report('[VERB] ',@_) if ($self->{'VERBOSE'});
    }
    return SUCCESS;
}


=pod

=item B<debug>(I<$debuglvl, @array>): boolean

Reports B<@array> using the B<report> method iff the current debug level is
higher or equal than I<$debuglvl>.

=cut

sub debug ($@) {
    my $self = shift;
    my $debuglvl = shift;

    # the first argument must be an integer
    unless($debuglvl =~ /^\d$/) {
        throw_error("debug: first parameter must be integer in [0-9], got",
            $debuglvl);
        return;
    }

    if (defined($self->{DEBUGLV}) && $self->{DEBUGLV} >= $debuglvl) {
        $self->syslog ('debug', @_);
        return $self->report('[DEBUG] ',@_);
    }
    return SUCCESS;
}


=pod

=item B<log>(I<@array>): boolean

Write I<@array> to the log file, if any.

=cut

sub log (@) {
    my $self = shift;

    my $string = join('', @_)."\n";
    $self->{'LOGFILE'}->print($string) if ($self->{'LOGFILE'});
    return SUCCESS;
}


=pod

=item B<syslog>(I<$priority, @array>);

Write I<@array> to the syslog, with the given priority.

=cut

sub syslog {
    my ($self, $priority, @msg) = @_;

    return unless $self->{LOGFILE} && $self->{LOGFILE}->{SYSLOG};
    # If syslog can't be reached do nothing, but please don't die.
    eval {
        openlog ($self->{LOGFILE}->{SYSLOG}, "pid", $self->{'FACILITY'});
        Sys::Syslog::syslog ($priority, join ('', @msg));
        closelog();
    }
}

1;

__END__

=pod

=back

=head1 SEE ALSO

L<LC::Exception>, L<CAF::Application>, L<CAF::Log>, L<CAF::Reporter>.

=cut


