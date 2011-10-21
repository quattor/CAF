# ${license-info}
# ${developer-info
# ${author-info}
# ${build-info}
#
################################################################################
#
# $Id: RepLogger.pm,v 1.2 2008/09/26 14:06:40 poleggi Exp $
#
################################################################################

################################################################################
# _RepObj class is just a front-end to CAF::ReporterMany from which it inherits
# the needed methods
################################################################################
package _RepObj;

use strict;
use vars qw(@ISA);
use CAF::Object;
use CAF::ReporterMany;
use LC::Exception qw(SUCCESS);
my $ec = LC::Exception::Context->new->will_store_all;

@ISA = qw(CAF::Object CAF::ReporterMany);

sub new () {
    my $class = shift;

    my $self = {};
    unless($self = $class->SUPER::new()) {
        $ec->rethow_error;
        return;
    }
    return $self;
}

# This is dummy, just to make CAF::Object happy ;-)
sub _initialize() {
    return SUCCESS;
}


################################################################################
# CAF::RepLogger class has two objects
#   _RepObj's instance
#   CAF::Log's instance
################################################################################
package CAF::RepLogger;

BEGIN{
    use Exporter;
    use vars qw(@ISA @EXPORT @EXPORT_OK $VERSION);
    @ISA       = qw(Exporter);
    @EXPORT    = qw();
    @EXPORT_OK = qw(
        setup_replogger
        log_debug
        log_error
        log_info
        log_ok
        log_verb
        log_warn
    );
    $VERSION = sprintf("%d.%02d", q$Revision: 1.2 $ =~ /(\d+)\.(\d+)/);
}

use strict;
use CAF::Log;
use LC::Exception qw(SUCCESS throw_error);

=pod

=head1 NAME

CAF::RepLogger - Class for console & log message reporting for generic
applications

=head1 SYNOPSIS

=head2 Object-oriented usage

Allow for more objects to be instantiated, thus several log files can be used.

    use CAF::RepLogger;
    use LC::Exception;

    my $logger;
    unless($logger = CAF::RepLogger->new(
        'log-file'  => $0.'.log',
        # no report on console
        'quiet      => 1')) {
        my $err = $ec->error;
        $ec->ignore_error;
        die "$err\n";
    }
    $logger->warn('ahem...');
    $logger->error('ouch!');


=head2  Procedural usage

Only a single log file can be used.

    use CAF::RepLogger qw(
        setup_replogger log_debug log_ok log_verb);
    use LC::Exception;

    my $ec = LC::Exception::Context->new->will_store_all;

    unless(setup_replogger(
            'debug-level'   => 3,
            'log-file'      => $0.'.log',
            'verbose'       => 1)) {
        my $err = $ec->error;
        $ec->ignore_error;
        die "$err\n";
    }

    log_debug(3, 'foo debug');
    log_ok('all fine');
    log_verb('blah, blah');


=head1 INHERITANCE

L<CAF::Object>, L<CAF::Reporter>.

=head1 DESCRIPTION

This modules provides console message reporting and logging facilities to
applications which can either be or not CAF-based, and want one or more
log files. It inherits from CAF::Reporter and uses a CAF::Log's object.

Multiple logs can be handled via the object-oriented interface, so that, if
your application is composed of more modules, each of them can instantiate
a different RepLogger object. Conversely, a one-for-all log mode is obtained
through the procedural interface which uses a shared configuration.

=over

=cut

###############################################################################
# Private data
###############################################################################
# my $ec = LC::Exception::Context->new->will_store_all;

# Setup structure with defaults
my %_replogger_setup = (
    'debug-level'   => 0,
    'log-file'      => undef,
    'log-file-opt'  => 'at',
    'quiet'         => 0,
    'session-ids'   => [],
    'stack-frame'   => 0,
    'verbose'       => 0,
    'facility'      => 'local1',
    'rep-obj'       => undef  # A _RepObj's object
);


###############################################################################
# Private functions
###############################################################################

###############################################################################
# who_is(): string
#
# return a string formatted as
#
#     '[<session-ids>] <module-name>::<caller-subroutine>: '
#
# where '[<session-ids>]' and '<module-name>::<caller-subroutine>: ' may be
# printed or not, depending on the configuration options 'session-ids' and
# 'stack-frame'.
###############################################################################
sub who_is() {

    my $res = '';
    if(defined $_replogger_setup{'session-ids'} and
        @{$_replogger_setup{'session-ids'}}) {
        my $sess_id = '';
        # each item is supposed to be a string reference
        foreach my $ref (@{$_replogger_setup{'session-ids'}}) {
            $sess_id .= (($ref and $$ref) || '-').' ';
        }
        $sess_id =~ s/\s+$//;
        $res .= '['.$sess_id.'] ';
    }

    if($_replogger_setup{'stack-frame'}) {
        my $subr_name = (caller($_replogger_setup{'stack-frame'}+1))[3];
        # keep only the last namespace
        if($subr_name) {
            $subr_name =~ s/^\S+::(\w+::\w+)$/$1/;
            $res .= "$subr_name: ";
        }
    }

    return $res;
}


###############################################################################
# Public functions
###############################################################################

=head1 Public methods/functions

For each of the following items, the first name is the OO interface's method,
the second name is procedural interface's function.

=over

=item B<new, setup_replogger> I<(%module_options)>

Initialize LoggerSingle with options passed in a hash. B<new> is used with the
OO interface, B<setup_replogger> with the procedural interface. Options are

=over

=item I<debug-level> integer [0-9]

Default is 0.

=item I<log-file> string

Absolute path: check permissions! B<Mandatory>.

=item I<log-file-opt> string

Options to be passed to L<CAF::Log>. Default is 'at' (append, timestamp).

=item I<quiet> boolean [0,1]

Disable logging to the console. Default is 0.

=item I<session-ids> array reference

Pointer to a list of pointers to extra information tokens which are logged
enclosed in square brackets; the line will look like

    [<type-tag>] [<session-ids>] <message>

where each token in <session-ids> is replaced by a dash '-', when the token
itself is undefined at logging time. This is useful when session information is
recorded in some global variables which might be undefined, so one would code:

    my ($sid, $uid);
    setup_replogger('log-file' => 'mylog', 'session-ids' => [\$sid, \$uid]);
    log_ok('initialized');
    # prints
    #   [OK] [- -] initialized
    ...
    # wait for session information to be there
    ($sid, $uid) = ('sessX', 'userY');
    log_ok('session open');
    # prints
    #   [OK] [sessX userY] session open

Default is undef.

=item I<stack-frame> integer [0-N]

If > 0, enable printing of the stack frame corresponding to the depth value
given. For instance, if your code is

    sub my_fun1 {
        log_error('ouch!');
    }
    sub my_fun2 {
        my_fun1;
    }
    my_fun2;

and you set, respectively, 'stack-frame', to 0, 1 and 2, you get

    ... ouch!
    ... main::my_fun1: ouch!
    ... main::my_fun2: ouch!

Default is 0.

=item I<verbose> boolean [0,1]

Enable logging of messages passed to B<[log_]verb()>. Default is 0.

=back

=cut
###############################################################################
sub new($@) {
    my $class = shift;

    unless(setup_replogger(@_)) {
        $ec->rethrow_error;
        return;
    }

    my $self = {};
    # physical copy to allow multiple instances
    %{$self} = %_replogger_setup;
    bless($self, $class);

    return $self;
}
sub setup_replogger(@) {
    my %h_setup = @_;

    # set options from the input hash
    foreach my $opt (keys %_replogger_setup) {
        if(exists $h_setup{$opt}) {
            $_replogger_setup{$opt} = $h_setup{$opt};
            delete $h_setup{$opt};
        }
    }
    # check for any unmatched left over
    if(%h_setup) {
        throw_error('Unknown option(s)', join(' ', sort keys %h_setup));
        return;
    }

    unless($_replogger_setup{'rep-obj'} = _RepObj->new()) {
        throw_error('Cannot create reporter instance', $ec->error);
        return;
    }

    $_replogger_setup{'quiet'} = 1 if($_replogger_setup{'quiet'});
    $_replogger_setup{'verbose'} = 1 if($_replogger_setup{'verbose'});

    unless($_replogger_setup{'rep-obj'}->setup_reporter(
            $_replogger_setup{'debug-level'},
            $_replogger_setup{'quiet'},
            $_replogger_setup{'verbose'},
            $_replogger_setup{'facility'})) {
        throw_error('Cannot set up reporter', $ec->error);
        return;
    }

    if($_replogger_setup{'log-file'}) {
        my $logger;
        unless($logger = CAF::Log->new(
                $_replogger_setup{'log-file'},
                $_replogger_setup{'log-file-opt'})) {
            throw_error('Cannot create logger instance', $ec->error);
            return;
        }
        unless($_replogger_setup{'rep-obj'}->set_report_logfile($logger)) {
            throw_error('Cannot set log file', $ec->error);
            return;
        }
    }

    if($_replogger_setup{'debug-level'} and
            $_replogger_setup{'debug-level'} !~ /^\d$/) {
        throw_error("'debug-level': must be integer in [0-9], got",
            $_replogger_setup{'debug-level'});
        return;
    }
    if($_replogger_setup{'stack-frame'} and
            $_replogger_setup{'stack-frame'} !~ /^\d$/) {
        throw_error("'stack-frame': must be integer, got",
            $_replogger_setup{'stack-frame'});
        return;
    }

    return SUCCESS;
}

###############################################################################

=item B<*, log_*> I<(;@messages)>

Logging functions. * is one of:

    debug
    error
    info
    ok
    warn

So, f.i., you would say either

    $logger->debug(2, 'this is debug');

or

    log_debug(2, 'this is debug');

=cut
###############################################################################
sub debug($$;@) {
    my $self = shift;
    $self->{'rep-obj'}->debug(shift, who_is(), @_);
}
sub log_debug($;@) {
    $_replogger_setup{'rep-obj'}->debug(shift, who_is(), @_);
}
sub error($;@) {
    my $self = shift;
    $self->{'rep-obj'}->error(who_is(), @_);
}
sub log_error(;@) {
    $_replogger_setup{'rep-obj'}->error(who_is(), @_);
}
sub info($;@) {
    my $self = shift;
    $self->{'rep-obj'}->info(who_is(), @_);
}
sub log_info(;@) {
    $_replogger_setup{'rep-obj'}->info(who_is(), @_);
}
sub ok($;@) {
    my $self = shift;
    $self->{'rep-obj'}->OK(who_is(), @_);
}
sub log_ok(;@) {
    $_replogger_setup{'rep-obj'}->OK(who_is(), @_);
}
sub verb($;@) {
    my $self = shift;
    $self->{'rep-obj'}->verbose(who_is(), @_);
}
sub log_verb(;@) {
    $_replogger_setup{'rep-obj'}->verbose(who_is(), @_);
}
sub warn($;@) {
    my $self = shift;
    $self->{'rep-obj'}->warn(who_is(), @_);
}
sub log_warn(;@) {
    $_replogger_setup{'rep-obj'}->warn(who_is(), @_);
}

1;

=back

=head1 SEE ALSO

L<CAF::Log(3)>, L<CAF::Reporter(3)>

=head1 AUTHOR

Marco Emilio Poleggi <Marco.Poleggi@cern.ch>

=head1 LICENSE

L<http://www.edg.org/license.html>

=head1 VERSION

$Id: RepLogger.pm,v 1.2 2008/09/26 14:06:40 poleggi Exp $

=cut
