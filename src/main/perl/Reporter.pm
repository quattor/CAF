# ${license-info}
# ${developer-info}
# ${author-info}
# ${build-info}

package CAF::Reporter;

use strict;
use LC::Exception qw (SUCCESS throw_error);
use Sys::Syslog qw (openlog closelog);

use vars qw(@ISA $_REP_SETUP);



=pod

=head1 NAME

CAF::Reporter - Class for console & log message reporting in CAF applications

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

=over

=cut


BEGIN {
  # setup default values for reporter
  $_REP_SETUP={
            'VERBOSE'  => 0,        # no verbose
            'DEBUGLV'  => 0,        # no debug
            'QUIET'    => 0,        # don't be quiet
            'LOGFILE'  => undef,    # no log file
            'FACILITY' => 'local1'  # syslog facility
    }
}


#------------------------------------------------------------
#                      Public Methods/Functions
#------------------------------------------------------------

=pod

=back

=head2 Public methods

=over 4

=item setup_reporter ($debuglvl,$quiet,$verbose,$facility): boolean

Reporter setup:

- $debuglvl sets the (highest) debug level, for messages reported with
  the 'debug' method.
  The following recommendations apply:
   0: no debug information
   1: main package
   2: main libraries/functions
   3: helper libraries
   4: core functions (constructors, destructors)

- $quiet: if set to a true value (eg. 1), stops any output to console.

- $verbose: if set to a true value (eg. 1), produce verbose output
            (produced with the 'verbose' method). Implied by debug >= 1.

- $facility: syslog facility the messages will be sent to

=cut

sub setup_reporter {
  my ($self,$debuglvl,$quiet,$verbose,$facility)=@_;

  $_REP_SETUP->{'DEBUGLV'}= defined $debuglvl && $debuglvl > 0 ? $debuglvl : 0;
  $_REP_SETUP->{'QUIET'} = defined $quiet && $quiet ? 1 : 0;
  $_REP_SETUP->{'VERBOSE'} = ((defined $verbose && $verbose) || (defined $debuglvl && $debuglvl)) ? 1 : 0;
  $_REP_SETUP->{'FACILITY'} = $facility unless !defined $facility;

  return SUCCESS;
}



=pod

=item set_report_logfile($logfile): bool


If $logfile is defined, it will be used as log file. $logfile can be
any type of class object reference, but must the object must support a
'print(@array)' method. Typically, it should be an CAF::Log
instance. If $logfile is undefined (undef), no log file will be used.

=cut

sub set_report_logfile {
  my ($self,$logfile)=@_;

  $_REP_SETUP->{'LOGFILE'}=$logfile;

  return SUCCESS;
}






=pod

=item report(@array): boolean

Report general information about the program progression. The output
to the console is supressed if 'quiet' is set. The strings in @array
are concatenated and sent as a single line to the output(s).

=cut

sub report {
  my $self=shift;
  my $string=join('',@_)."\n";
  print $string unless ($_REP_SETUP->{'QUIET'});
  $self->log(@_);
  return SUCCESS;
}


=pod

=item info (@array): boolean

Reports @array using the 'report' method, but with a '[INFO]' prefix.

=cut

sub info (@) {
  my $self=shift;
  $self->syslog ('info', @_);
  return $self->report('[INFO] ',@_);
}


=pod

=item OK (@array): boolean

Reports @array using the 'report' method, but with a '[OK]' prefix.

=cut


sub OK (@) {
  my $self=shift;
  $self->syslog ('notice', @_);
  return $self->report('[OK]   ',@_);
}


=pod

=item warn (@array): boolean

Reports @array using the 'report' method, but with a '[WARN]' prefix.

=cut


sub warn (@) {
  my $self=shift;
  $self->syslog ('warning', @_);
  return $self->report('[WARN] ',@_);
}

=pod

=item warn (@array): boolean

Reports @array using the 'report' method, but with a '[ERROR]' prefix.

=cut


sub error (@) {
  my $self=shift;
  $self->syslog ('err', @_);
  return $self->report('[ERROR] ',@_);
}


=pod

=item verbose (@array): boolean

Reports @array using the 'report' method, but only if 'verbose' is set
to 1. Output is prefixed with [VERB].

=cut

sub verbose (@) {
  my $self=shift;
  if ($_REP_SETUP->{VERBOSE}) {
    $self->syslog ('notice', @_);
    return $self->report('[VERB] ',@_) if ($_REP_SETUP->{'VERBOSE'});
  }
  return SUCCESS;
}




=pod

=item debug ($debuglvl,@array): boolean

Reports @array using the 'report' method iff the current debug level is
higher or equal than $debuglvl.

=cut


sub debug {
  my $self=shift;
  my $debuglvl=shift;

  # the first argument must be an integer
  unless($debuglvl =~ /^\d$/) {
    throw_error("debug: first parameter must be integer in [0-9], got",
        $debuglvl);
    return;
  }

  if (defined($_REP_SETUP->{DEBUGLV}) && $_REP_SETUP->{DEBUGLV} >= $debuglvl) {
    $self->syslog ('debug', @_);
    return $self->report('[DEBUG] ',@_);
  }
  return SUCCESS;
}



=pod

=item log (@array): boolean

Writes @array to the log file, if any.

=cut



sub log {
  my $self=shift;
  my $string=join('',@_)."\n";
  $_REP_SETUP->{'LOGFILE'}->print($string) if ($_REP_SETUP->{'LOGFILE'});
  return SUCCESS;
}

=pod

=item syslog ($priority, @array);

Writes @array to the syslog, with the given priority.

=cut
sub syslog {
  my ($self, $priority, @msg) = @_;

  return unless $_REP_SETUP->{LOGFILE} &&
      exists ($_REP_SETUP->{LOGFILE}->{SYSLOG});
  # If syslog can't be reached do nothing, but please don't die.
  eval {
    openlog ($_REP_SETUP->{LOGFILE}->{SYSLOG}, "pid", $_REP_SETUP->{'FACILITY'});
    Sys::Syslog::syslog ($priority, join ('', @msg));
    closelog();
  }
}

=pod

=back

=head2 Private methods

=over 4

=cut

#=item DESTROY
#
#Called upon garbage collection time. Closes the logfile, if any.
#
#=cut

#sub DESTROY {
#  $_REP_SETUP->{'LOGFILE'}->close() if (defined $_REP_SETUP->{'LOGFILE'});
#}




=pod

=back

=cut

1; ## END ##
