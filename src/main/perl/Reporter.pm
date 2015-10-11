# ${license-info}
# ${developer-info}
# ${author-info}
# ${build-info}

package CAF::Reporter;

use strict;
use warnings;

use LC::Exception qw (SUCCESS throw_error);
use Sys::Syslog qw (openlog closelog);

use CAF::History qw($EVENTS);

use vars qw($_REP_SETUP);
use parent qw(Exporter);

use Readonly;

Readonly our $VERBOSE => 'VERBOSE';
Readonly our $DEBUGLV => 'DEBUGLV';
Readonly our $QUIET => 'QUIET';
Readonly our $LOGFILE => 'LOGFILE';
Readonly our $SYSLOG => 'SYSLOG';
Readonly our $FACILITY => 'FACILITY';
Readonly our $HISTORY => 'HISTORY';
Readonly our $WHOAMI => 'WHOAMI';

our @EXPORT_OK = qw($VERBOSE $DEBUGLV $QUIET
    $LOGFILE $SYSLOG $FACILITY
    $HISTORY $WHOAMI
);


my $_reporter_default = {
    $VERBOSE  => 0,        # no verbose
    $DEBUGLV  => 0,        # no debug
    $QUIET    => 0,        # don't be quiet
    $LOGFILE  => undef,    # no log file
    $FACILITY => 'local1', # syslog facility
};

# setup the initial/default _REP_SETUP
init_reporter();

# Return the hashref that holds the reporter setup
# Instances of CAF::Reporter store the reporter config in "global" _REP_SETUP
# This is for subclassing ReporterMany
sub _rep_setup
{
    my $self = shift;
    return $_REP_SETUP;
}

=pod

=head1 NAME

C<CAF::Reporter> - Class for console & log message reporting in CAF applications

=head1 SYNOPSIS

    package myclass;
    use CAF::Log;
    use parent qw(CAF::Reporter);

    my $logger = CAF::Log->new('/path/to/logfile', 'at');

    sub new {
        ...
        $self->setup_reporter(2, 0, 1);
        $self->set_report_logfile($logger);
        ...
    }

    sub foo {
        my ($self, $a, $b, $c) = @_;
        ...
        $self->report("foo is doing well");
        $self->verbose("foo called with params $a $b $c");
        $self->debug(3, "foo is performing operation xyz");
        ...
    }

=head1 DESCRIPTION

C<CAF::Reporter> provides class methods for message (information,
warnings, error) reporting to standard output and a log file. There is
only one instance of C<CAF::Reporter> in an application. (All C<CAF::Reporter>
instances share the same configuration).
Classes wanting to use C<CAF::Reporter> have to inherit from it
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
            (with the C<verbose> method). Implied by debug >= 1.

=item C<$facility>: syslog facility the messages will be sent to

=back

If any of these arguments is C<undef>, current application settings
will be preserved.

=cut

# Written with the indented 'if defined' to make clear that
# nothing happens when undef is set for a certain value

sub setup_reporter
{
    my ($self, $debuglvl, $quiet, $verbose, $facility) = @_;

    $self->_rep_setup()->{$DEBUGLV} = ($debuglvl > 0 ? $debuglvl : 0)
        if defined($debuglvl);
    $self->_rep_setup()->{$QUIET} = ($quiet ? 1 : 0)
        if defined($quiet);
    $self->_rep_setup()->{$VERBOSE} = (($verbose || $self->_rep_setup()->{$DEBUGLV}) ? 1 : 0)
        if (defined ($verbose) || defined($debuglvl));
    $self->_rep_setup()->{$FACILITY} = $facility
        if defined($facility);

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

    $self->_rep_setup()->{$LOGFILE} = $logfile;

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
    # Ensure that there is no undefined arg: replace by <undef> if any.
    my @args = map {defined($_) ? $_ : '<undef>'} @_;
    my $string = join('', @args)."\n";
    _print($string) unless ($self->_rep_setup()->{$QUIET});
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
    return $self->report('[INFO] ', @_);
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
    return $self->report('[OK]   ', @_);
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
    return $self->report('[WARN] ', @_);
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

# TODO: the previous code had additional 'if ($self->_rep_setup()->{'VERBOSE'})' after the report.
#       was the even older behaviour maybe to always syslog, and only report on verbose?
#       report has something similar with quiet and log()

sub verbose
{
    my $self = shift;

    if ($self->_rep_setup()->{$VERBOSE}) {
        $self->syslog ('notice', @_);
        return $self->report('[VERB] ', @_);
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

    # the first argument must be a single-digit integer
    $debuglvl = "<undef>" if (! defined($debuglvl));
    unless($debuglvl =~ /^\d$/) {
        throw_error("debug: first parameter must be integer in [0-9], got $debuglvl");
        return;
    }

    if (defined($self->_rep_setup()->{$DEBUGLV}) && $self->_rep_setup()->{$DEBUGLV} >= $debuglvl) {
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
    $self->_rep_setup()->{$LOGFILE}->print($string) if ($self->_rep_setup()->{$LOGFILE});
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

    return unless $self->_rep_setup()->{$LOGFILE} &&
        exists ($self->_rep_setup()->{$LOGFILE}->{$SYSLOG});

    # If syslog can't be reached do nothing, but please don't die.
    local $@;
    eval {
        openlog ($self->_rep_setup()->{$LOGFILE}->{$SYSLOG},
                 "pid",
                 $self->_rep_setup()->{$FACILITY});
        Sys::Syslog::syslog ($priority, join ('', @msg));
        closelog();
    };

    return;
}

=pod

=item init_history

Create a L<CAF::History> instance to track events.
Argument C<keepinstances> is passed to the C<CAF::History>
initialization.

=cut

sub init_history
{
    my ($self, $keepinstances) = @_;

    $self->{$HISTORY} = CAF::History->new($keepinstances);

    return SUCCESS;
}


=pod

=item event

If a C<CAF::History> is initialized, track the event. The following metadata is added

=over

=item C<$WHOAMI>

Current class name C<ref($self)>.

=back

=cut

sub event
{
    my ($self, $obj, %metadata) = @_;

    my $hist = $self->{$HISTORY};
    return SUCCESS if (! defined($hist->{$EVENTS}));

    $metadata{$WHOAMI} = ref($self);

    return $hist->event($obj, %metadata);
}

=pod

=back

=cut

1;
