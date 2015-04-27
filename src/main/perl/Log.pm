# ${license-info}
# ${developer-info}
# ${author-info}
# ${build-info}

package CAF::Log;

use strict;
use CAF::Object;
use vars qw(@ISA);
use LC::Exception qw (SUCCESS throw_error);
use FileHandle;

my $ec = LC::Exception::Context->new->will_store_all;

@ISA = qw(CAF::Object);

=pod

=head1 NAME

CAF::Log - Simple class for handling log files

=head1 SYNOPSIS


  use CAF::Log;

  my $log=CAF::Log->new('/foo/bar','at');

  $log->print("this goes to the log file\n");
  $log->close();

=head1 INHERITANCE

  CAF::Reporter

=head1 DESCRIPTION

The B<CAF::Log> class allows to instantiate objects for writing log files.
A log file line can be prefixed by a time stamp.


=over

=cut

#------------------------------------------------------------
#                      Public Methods/Functions
#------------------------------------------------------------

=pod

=back

=head2 Public methods

=over 4

=item close(): boolean

closes the log file.

=cut

sub close ($) {
  my $self=shift;

  return undef unless (defined $self->{'FH'});
# Why adding extra newlines???
#   $self->{'FH'}->print("\n");
  $self->{'FH'}->close();
  $self->{'FH'} = undef;

  return SUCCESS;
}



=pod

=item print($string):boolean

prints a line into the log file.

=cut

sub print ($$) {
  my ($self,$msg) = @_;

  if (defined $self->{'TSTAMP'}) {
    # print timestamp the SUE way ;-)
    my ($sec, $min, $hour, $mday, $mon, $year) = localtime(time);
    $msg = sprintf("%04d/%02d/%02d-%02d:%02d:%02d %s",
		   $year+1900, $mon+1, $mday, $hour, $min, $sec,$msg);
  }
  return $self->{'FH'}->print($msg);
}


=pod

=back

=head2 Private methods

=over 4

=item _initialize($filename,$options)

initialize the object. Called by new($filename,$options).

$options can be 'a' for appending to a logfile, and 'w' for
truncating, and 't' for generating a timestamp on every
print. If the 'w' option is used and there was a previous
log file, it is renamed with the extension '.prev'.

Examples:
open('/foo/bar','at'): append, enable timestamp
open('/foo/bar','w') : truncate logfile, no timestamp


=cut

sub _initialize ($$$) {
  my ($self,$filename,$options) = @_;

  $self->{'FILENAME'} = $filename;
  $self->{'OPTS'} = $options;

  if ($self->{FILENAME} =~ m{([^/]*).log$}) {
    $self->{SYSLOG} = $1;
  }

  unless ($self->{'OPTS'} =~ /^(w|a)t?$/) {
    throw_error("Bad options for log ".$self->{'FILENAME'}.
                      ": ".$self->{'OPTS'});
    return undef;
  }

  if ($self->{'OPTS'} =~ /t/) {
    $self->{'TSTAMP'}=1;
  }

  if ($self->{'OPTS'} =~ /w/) {
    #
    #  Move old filename away if mode is 'w'.
    #
    rename ($self->{'FILENAME'},$self->{'FILENAME'}.'.prev')
      if (-e $self->{'FILENAME'});
    unless ($self->{'FH'} = FileHandle->new(">".$self->{'FILENAME'})) {
      throw_error("Open for write ",$self->{'FILENAME'});
      return undef;
    }
  } else {
    #
    #  Mode is 'a'. Append to (potentially existing) file
    #
    unless ($self->{'FH'} = FileHandle->new(">> ".$self->{'FILENAME'})) {
      throw_error("Open for append: $self->{'FILENAME'}", $!);
      return undef;
    }
  }
  #
  # Autoflush on
  #
  $self->{'FH'}->autoflush();

  return SUCCESS;

}

=pod

=item DESTROY

called during garbage collection. Invokes close()

=cut


sub DESTROY {
  my $self = shift;
  $self->close() if (defined $self->{'FH'});
}

=pod

=back

=cut


END {
    # report all stored warnings
    foreach my $warning ($ec->warnings) {
        warn("[WARN] $warning");
    }
    $ec->clear_warnings;
}

1; ## END ##
