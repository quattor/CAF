# ${license-info}
# ${developer-info}
# ${author-info}
# ${build-info}

package CAF::Reporter;

use strict;
use LC::Exception qw (SUCCESS throw_error);
use Sys::Syslog qw (openlog closelog);

use vars qw(@ISA $_REP_SETUP);
use Readonly;

Readonly my $VERBOSE => 'VERBOSE';
Readonly my $DEBUGLV => 'DEBUGLV';
Readonly my $QUIET => 'QUIET';
Readonly my $LOGFILE => 'LOGFILE';
Readonly my $SYSLOG => 'SYSLOG';
Readonly my $FACILITY => 'FACILITY';

my $_reporter_default = {
    $VERBOSE  => 0,        # no verbose
    $DEBUGLV  => 0,        # no debug
    $QUIET    => 0,        # don't be quiet
    $LOGFILE  => undef,    # no log file
    $FACILITY => 'local1', # syslog facility
};

# setup the initial/default _REP_SETUP
init_reporter();

=pod

=head1 NAME

C<CAF::Reporter> - Class for console & log message reporting in CAF applications

=head1 SYNOPSIS

    package myclass;
    use CAF::Reporter;
    @ISA = qw(CAF::Reporter);
    ...
    sub foo {
        my ($self,$a,$b,$c)=@_;
        ...
        $self->report("foo is doing well");
        $self->verbose("foo called with params $a $b $c");
        $self->debug(3, "foo is performing operation xyz");
        ...
    }

=head1 DESCRIPTION

C<CAF::Reporter> provides class methods for message (information,
warnings, error) reporting to standard output and a log file. There is
only one instance of C<CAF::Reporter> in an application. Classes
wanting to use C<CAF::Reporter> have to inherit from it
(using C<parent qw(CAF::Reporter)> or via C<@ISA>).

Usage of a log file is optional. A log file can be attached/detached
with the C<set_logfile> method.

=head2 Public methods

=over 5

=item init_reporter

Setup default/initial values for reporter. Returns success.

=cut

sub init_reporter
{
    $_REP_SETUP = { %$_reporter_default };

    return SUCCESS;
}

=pod

=item C<setup_reporter ($debuglvl, $quiet, $verbose, $facility)>: boolean

Reporter setup:

=over

=item  C<$debuglvl> sets the (highest) debug level, for messages reported with
    the 'debug' method.
    The following recommendations apply:
        0: no debug information
        1: main package
        2: main libraries/functions
        3: helper libraries
        4: core functions (constructors, destructors)

=item C<$quiet>: if set to a true value (eg. 1), stops any output to console.

=item C<$verbose>: if set to a true value (eg. 1), produce verbose output
            (produced with the C<verbose> method). Implied by debug >= 1.

=item C<$facility>: syslog facility the messages will be sent to

=back

=cut

sub setup_reporter
{
    my ($self, $debuglvl, $quiet, $verbose, $facility) = @_;

    $_REP_SETUP->{$DEBUGLV} = (defined($debuglvl) && $debuglvl > 0) ? $debuglvl : 0;
    $_REP_SETUP->{$QUIET} = $quiet ? 1 : 0;
    $_REP_SETUP->{$VERBOSE} = ($verbose || $_REP_SETUP->{$DEBUGLV}) ? 1 : 0;
    $_REP_SETUP->{$FACILITY} = $facility if defined($facility);

    return SUCCESS;
}

=pod

=item C<set_report_logfile($logfile)>: bool

If C<$logfile> is defined, it will be used as log file. C<$logfile> can be
any type of class object reference, but the object must support a
C<print(@array)> method. Typically, it should be an C<CAF::Log>
instance. If C<$logfile> is undefined, no log file will be used.

=cut

sub set_report_logfile
{
    my ($self, $logfile) = @_;

    $_REP_SETUP->{'LOGFILE'} = $logfile;

    return SUCCESS;
}

=pod

=item C<report(@array)>: boolean

Report general information about the program progression
to stdout (via C<print>) and C<log> method.
The output to the console is supressed if C<quiet> is set.
The strings in C<@array> are concatenated, newline is added
and sent as a single line to the output.
Then C<log> method is called with C<@array> (irrespective of C<quiet>).

The C<report> method does not log to syslog.

=cut

#TODO: always log? or also only unless quiet

# print whatever is passed
# (added for unittesting)
sub _print
{
    print @_;
}

sub report
{
    my $self = shift;
    my $string = join('', @_)."\n";
    _print($string) unless ($_REP_SETUP->{'QUIET'});
    $self->log(@_);
    return SUCCESS;
}


=pod

=item C<info(@array)>: boolean

Logs using C<syslog> method with C<info> priority
and reports C<@array> using the C<report> method, but with a C<[INFO]> prefix.

=cut

# TODO: prefixing length is based on longest prefix ERROR/DEBUG
#       (this used to be based on INFO/WARN/VERB)

sub info
{
    my $self = shift;
    $self->syslog ('info', @_);
    return $self->report('[INFO]  ', @_);
}


=pod

=item C<OK(@array)>: boolean

Logs using C<syslog> method with C<notice> priority
and reports C<@array> using the C<report> method, but with a C<[OK]> prefix.

=cut

sub OK
{
    my $self = shift;
    $self->syslog('notice', @_);
    return $self->report('[OK]    ', @_);
}


=pod

=item C<warn(@array)>: boolean

Logs using C<syslog> method with C<warning> priority
and reports C<@array> using the C<report> method, but with a C<[WARN]> prefix.

=cut


sub warn
{
    my $self = shift;
    $self->syslog('warning', @_);
    return $self->report('[WARN]  ', @_);
}

=pod

=item C<error(@array)>: boolean

Logs using C<syslog> method with C<err> priority
and reports C<@array> using the C<report> method, but with a C<[ERROR]> prefix.

=cut

sub error
{
    my $self = shift;
    $self->syslog('err', @_);
    return $self->report('[ERROR] ', @_);
}

=pod

=item C<verbose(@array)>: boolean

If C<verbose> is enabled (via C<setup_reporter>), the C<verbose> method
logs using C<syslog> method with C<notice> priority
and reports C<@array> using the C<report> method, but with a C<[VERB]> prefix.

=cut

# TODO: the previous code had additional 'if ($_REP_SETUP->{'VERBOSE'})' after the report.
#       was the even older behaviour maybe to always syslog, and only report on verbose?
#       report has something similar with quiet and log()

sub verbose
{
    my $self = shift;

    if ($_REP_SETUP->{VERBOSE}) {
        $self->syslog ('notice', @_);
        return $self->report('[VERB]  ', @_);
    }

    return SUCCESS;
}

=pod

=item C<debug($debuglvl, @array)>: boolean

If C<$debuglvl> is higher or equal than then one set via C<setup_reporter>,
the C<debug> method
logs to syslog with C<debug> priority
and reports C<@array> using the C<report> method, but with a C<[DEBUG]> prefix.

If the C<$debuglvl> is not an integer in interval [0-9], an error is thrown
and undef returned (and nothing logged).

=cut


sub debug
{
    my $self = shift;
    my $debuglvl = shift;

    # the first argument must be a single integer
    $debuglvl = "<undef>" if (! defined($debuglvl));
    unless($debuglvl =~ /^\d$/) {
        throw_error("debug: first parameter must be integer in [0-9], got $debuglvl");
        return;
    }

    if (defined($_REP_SETUP->{$DEBUGLV}) && $_REP_SETUP->{$DEBUGLV} >= $debuglvl) {
        $self->syslog ('debug', @_);
        return $self->report('[DEBUG] ',@_);
    }

    return SUCCESS;
}

=pod

=item C<log(@array)>: boolean

Writes C<@array> as a concatenated string with added newline
to the log file, if one is setup (via C<set_report_logfile>).

=cut

sub log
{
    my $self = shift;
    my $string = join('', @_)."\n";
    $_REP_SETUP->{$LOGFILE}->print($string) if ($_REP_SETUP->{$LOGFILE});
    return SUCCESS;
}

=pod

=item C<syslog($priority, @array)>

Writes C<@array> as concatenated string to syslog, with the given priority.

Nothing will happen is no 'SYSLOG' attribute of logfile is set.
This attribute is prepended to every message.

(Return value is always undef.)

=cut

# TODO: Get rid of eval and  use 'nofatal,pid' as logopt
# TODO: Set useful return messages?

sub syslog
{
    my ($self, $priority, @msg) = @_;

    return unless $_REP_SETUP->{$LOGFILE} &&
        exists ($_REP_SETUP->{$LOGFILE}->{$SYSLOG});

    # If syslog can't be reached do nothing, but please don't die.
    eval {
        openlog ($_REP_SETUP->{$LOGFILE}->{$SYSLOG}, "pid", $_REP_SETUP->{$FACILITY});
        Sys::Syslog::syslog ($priority, join ('', @msg));
        closelog();
    };

    return;
}

=pod

=back

=cut

1;
