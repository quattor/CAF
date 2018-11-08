#${PMpre} CAF::Reporter${PMpost}

use LC::Exception qw (SUCCESS throw_error);
use Sys::Syslog qw (openlog closelog);

use Data::Dumper;
use CAF::Log qw($SYSLOG);
use CAF::History qw($EVENTS);
use CAF::TextRender qw(get_template_instance);
use JSON::XS;
use Storable qw(dclone);

use vars qw($_REP_SETUP);
use parent qw(Exporter);

use Readonly;

# Speedup _make_message_string
# expires after 3 seconds (mainly intended for reused _print / log / syslog)
use Memoize;
use Memoize::Expire;
tie my %cache => 'Memoize::Expire', LIFETIME => 3;
memoize '_make_message_string', SCALAR_CACHE => [HASH => \%cache ];

# Hold the JSON::XS instance for struct CEEsyslog
my $_ceelog_jsonxs;

Readonly our $VERBOSE => 'VERBOSE';
Readonly our $DEBUGLV => 'DEBUGLV';
Readonly our $QUIET => 'QUIET';
Readonly our $LOGFILE => 'LOGFILE';
Readonly our $FACILITY => 'FACILITY';
Readonly our $HISTORY => 'HISTORY';
Readonly our $WHOAMI => 'WHOAMI';
Readonly our $VERBOSE_LOGFILE => 'VERBOSE_LOGFILE';
Readonly our $STRUCT => 'STRUCT';


our @EXPORT_OK = qw($VERBOSE $DEBUGLV $QUIET
    $LOGFILE $SYSLOG $FACILITY
    $HISTORY $WHOAMI
    $VERBOSE_LOGFILE $STRUCT
);

# Very limited: no include path, strict interpretation, no recursion
my $_tt_inst = get_template_instance([], STRICT => 1, RECURSION => 0);


my $_reporter_default = {
    $VERBOSE  => 0,        # no verbose
    $DEBUGLV  => 0,        # no debug
    $QUIET    => 0,        # don't be quiet
    $LOGFILE  => undef,    # no log file
    $FACILITY => 'local1', # syslog facility
    $VERBOSE_LOGFILE => 0,
    $STRUCT => undef,
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

# Join all arguments into a single string
# Handles undefined arguments and non-printable garbage
# If last argument is a hashref, use the first arguments as template
# with last argument as data
sub _make_message_string
{
    my @args = @_;

    # Template with hashref
    my $do_template = ref($args[-1]) eq 'HASH';
    my $template_data;
    if ($do_template) {
        # Handle last arg as template data
        # Use a deep-copy, to prevent stringification type changes
        # for optional struct logger usage.
        $template_data = dclone(pop(@args));
    }

    # Ensure that there is no undefined arg: replace by <undef> if any, force stringification otherwise.
    @args = map {defined($_) ? "$_" : '<undef>'} @args;

    # Make single string
    my $string = join('', @args);

    if ($do_template) {
        # Try to use C<$string> as template

        local $Data::Dumper::Indent = 0;
        local $Data::Dumper::Terse = 1;
        my $res;
        if ($string eq '') {
            # only hashref passed
            $string = Dumper($template_data);
        } elsif ($_tt_inst->process(\$string, $template_data, \$res)) {
            $string = $res;
        } else {
            # the new "message" will contain the old template and data, so still useful
            $string = "Unable to process template '$string' with data " . Dumper($template_data) . ": " . $_tt_inst->error();
            # Don't die, but warn
            CORE::warn($string);
        }
    }

    # Replace any non-printable character with a ?
    # print charclass only includes whitespace that is not a control charater
    #    (so also add the space charclass (for e.g. newline))
    # TODO: also exclude the cntrl charclass?
    # TODO: this will remove non-ascii characters, incl. unicode;
    #       unless 'use utf8' (and similar) is used. :print: means printable in current encoding
    $string =~ s/[^[:print:][:space:]]/?/g;

    return $string;
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
        $self->config_reporter(debuglvl => 2, verbose => 1, logfile => $logger);
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

=over

=item init_reporter

Setup default/initial values for reporter. Returns success.

=cut

sub init_reporter
{
    $_REP_SETUP = { %$_reporter_default };

    return SUCCESS;
}


=item config_reporter

Reporter configuration:

Following options are supported

=over

=item debuglvl

Set the (highest) debug level, for messages reported with
the 'debug' method.
The following recommendations apply:

    0: no debug information
    1: main package
    2: main libraries/functions
    3: helper libraries
    4: core functions (constructors, destructors)

=item quiet

If set to a true value (eg. 1), stops any output to console.

=item verbose

If set to a true value (eg. 1), produce verbose output
(with the C<verbose> method). Implied by debug >= 1.

=item facility

The syslog facility the messages will be sent to

=item verbose_logfile

All reporting to logfiles will be verbose

=item logfile

C<logfile> can be any type of class object reference,
but the object must support a C<< print(@array) >> method.
Typically, it should be an C<CAF::Log> instance.

If C<logfile> is defined but false, no logfile will be used.

(The name is slightly misleading, because is it does not set the logfile's
filename, but the internal C<$LOGFILE> attribute).

=item struct

Enable the structured logging type C<struct> (implemented by method
C<< _struct_<struct> >>).

If C<struct> is defined but false, structured logging will be disabled.

=back

If any of these arguments is C<undef>, current application settings
will be preserved.

=cut

# Written with the indented 'if defined' to make clear that
# nothing happens when undef is set for a certain value

sub config_reporter
{
    my ($self, %opts) = @_;

    my $fail;

    $self->_rep_setup()->{$DEBUGLV} = ($opts{debuglvl} > 0 ? $opts{debuglvl} : 0)
        if defined($opts{debuglvl});
    $self->_rep_setup()->{$QUIET} = ($opts{quiet} ? 1 : 0)
        if defined($opts{quiet});
    $self->_rep_setup()->{$VERBOSE} = (($opts{verbose} || $self->_rep_setup()->{$DEBUGLV}) ? 1 : 0)
        if (defined ($opts{verbose}) || defined($opts{debuglvl}));
    $self->_rep_setup()->{$FACILITY} = $opts{facility}
        if defined($opts{facility});
    $self->_rep_setup()->{$VERBOSE_LOGFILE} = $opts{verbose_logfile}
        if defined($opts{verbose_logfile});
    $self->_rep_setup()->{$LOGFILE} = ($opts{logfile} ? $opts{logfile} : undef)
        if defined($opts{logfile});

    if (defined($opts{struct})) {
        if ($opts{struct}) {
            my $method = "_struct_$opts{struct}";
            if ($self->can($method)) {
                $self->_rep_setup()->{$STRUCT} = $method;
            } else {
                $fail = 1;
                $self->error("No method $method found for structured logging");
            }
        } else {
            # Do nothing
            $self->_rep_setup()->{$STRUCT} = undef;
        }
    }

    return $fail ? undef : SUCCESS;
}


=pod

=item C<init_logfile($filename, $options)>: bool

Create a new B<CAF::Log> instance with C<$filename> and C<$options> and
set it using C<config_reporter>.
Returns SUCCESS on success, undef otherwise.

(The method name is slightly misleading, because is it does
create the logfile with filename, but the internal
C<$LOGFILE> attribute).

=cut

sub init_logfile
{
    my ($self, $filename, $options) = @_;

    my $objlog = CAF::Log->new($filename, $options);
    if (! defined ($objlog)) {
        $self->verbose("cannot create Log $filename");
        return;
    }

    return $self->config_reporter(logfile => $objlog);
}

=pod

=item C<get_debuglevel>: int

Return current debuglevel

=cut

sub get_debuglevel
{
    my $self = shift;

    return $self->_rep_setup()->{$DEBUGLV};
}

=pod

=item C<is_quiet>: bool

Return true if reporter is quiet, false otherwise

=cut

sub is_quiet
{
    my $self = shift;

    return $self->_rep_setup()->{$QUIET} ? 1 : 0;
}

=pod

=item C<is_verbose>: bool

Return true if reporter is verbose, false otherwise

Supports boolean option C<verbose_logfile> to check if
reporting to logfile is verbose.

=cut

sub is_verbose
{
    my ($self, %opts) = @_;

    my $attr = $opts{verbose_logfile} ? $VERBOSE_LOGFILE : $VERBOSE;
    return $self->_rep_setup()->{$attr} ? 1 : 0;
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

    _print(_make_message_string(@_)."\n") unless ($self->_rep_setup()->{$QUIET});
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

If C<verbose> is enabled (via C<config_reporter>), the C<verbose> method
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
    } elsif ($self->_rep_setup()->{$VERBOSE_LOGFILE}) {
        return $self->log('[VERB] ', @_);
    }

    return SUCCESS;
}

=pod

=item C<debug($debuglvl, @array)>: boolean

If C<$debuglvl> is higher or equal than then one set via C<config_reporter>,
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
to the log file, if one is setup
(via C<< config_reporter(logfile => $loginst) >>).

If the last argument is a hashref and structured logging is enabled
(via C<< config_reporter(struct => $type) >>), call the structured
logging method with this hashref as argument.

=cut

sub log
{
    my $self = shift;

    $self->_rep_setup()->{$LOGFILE}->print(_make_message_string(@_)."\n") if ($self->_rep_setup()->{$LOGFILE});

    my $struct = $self->_rep_setup()->{$STRUCT};
    if ($struct && ref($_[-1]) eq 'HASH') {
        $self->$struct($_[-1]);
    }

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
        Sys::Syslog::syslog ($priority, _make_message_string(@msg));
        closelog();
    };

    return;
}

=item _struct_CEEsyslog

A structured logging method that uses CEE C<Common Event Expression> format
and reports it via syslog with info facility.

=cut

sub _struct_CEEsyslog
{
    my ($self, $data) = @_;

    if (!defined($_ceelog_jsonxs)) {
        # see also Log::Log4perl::Layout::JSON settings
        $_ceelog_jsonxs = JSON::XS->new()
            ->indent(0)          # to prevent newlines (and save space)
            ->ascii(1)           # to avoid encoding issues downstream
            ->allow_unknown(1)   # encode null on bad value (instead of exception)
            ->convert_blessed(1) # call TO_JSON on blessed ref, if it exists
            ->allow_blessed(1)   # encode null on blessed ref that can't be converted
            ->canonical(1);      # sort the keys, to create reproducable results
    }

    my $jsontxt;

    local $@;
    eval {
        $jsontxt = $_ceelog_jsonxs->encode($data);
    };
    if ($@) {
        local $Data::Dumper::Indent = 0;
        local $Data::Dumper::Terse = 1;
        # Don't die, but warn
        CORE::warn("Failed JSON::XS encoding data " . Dumper($data) . ": $@");
    } else {
        $self->syslog('info', '@cee: ', $jsontxt);

        return SUCCESS;
    }
}

=pod

=item C<set_report_history($historyinstance)>: bool

Set C<$historyinstance> as the reporter's history
(using the C<$HISTORY> attribute).

Returns SUCCESS on success, undef otherwise.

=cut

sub set_report_history
{
    my ($self, $historyinstance) = @_;

    $self->{$HISTORY} = $historyinstance;

    return SUCCESS;
}

=pod

=item init_history

Create a B<CAF::History> instance to track events.
Argument C<keepinstances> is passed to the C<CAF::History>
initialization.

Returns SUCCESS on success, undef otherwise.

=cut

sub init_history
{
    my ($self, $keepinstances) = @_;

    my $history = CAF::History->new($keepinstances);
    if (! defined ($history)) {
        $self->verbose("cannot create History");
        return;
    }

    return $self->set_report_history($history);
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

=head2 Deprecated/legacy methods

=over

=item setup_reporter

Deprecated method to configure the reporter.

The configure options C<debuglvl>, C<quiet>, C<verbose>, C<facility>, C<verbose_logfile>
are passed as postional arguments in that order.

    $self->setup_reporter(2, 0, 1);

is equal to

    $self->config_reporter(debuglvl => 2, quiet => 0, verbose => 1);

=cut

sub setup_reporter
{
    my ($self, @args) = @_;

    # ordered option names to pass to config_reporter
    my @legacy_pos_args = qw(debuglvl quiet verbose facility verbose_logfile);

    my %opts = map {$legacy_pos_args[$_] => $args[$_]} 0..$#args;

    return $self->config_reporter(%opts);

}

=pod

=item set_report_logfile

Deprecated method to configure the reporter C<LOGFILE> attribute:

    $self->setup_report_logfile($instance);

is equal to

    $self->config_reporter(logfile => $instance);

Returns SUCCESS on success, undef otherwise.

(The method name is slightly misleading, because is it does not set the logfile's
filename, but the internal C<$LOGFILE> attribute).

=cut

sub set_report_logfile
{
    my ($self, $loginstance) = @_;

    # Old behaviour when passing undef.
    $loginstance = 0 if (!defined($loginstance));

    return $self->config_reporter(logfile => $loginstance);
}

=pod

=back

=cut

1;
