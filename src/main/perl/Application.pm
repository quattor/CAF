# ${license-info}
# ${developer-info
# ${author-info}
# ${build-info}
#
#
# CAF::Application class
#
# Written by German Cancio <German.Cancio@cern.ch>
# (C) 2003 German Cancio & EU DataGrid http://www.edg.org
#

package CAF::Application;

use strict;
use vars qw(@ISA);
use CAF::Reporter;
use LC::Exception qw (SUCCESS throw_error);
use AppConfig qw (:argcount :expand);
use CAF::Object;
use CAF::Log;
use File::Basename;
use POSIX;

@ISA=qw(CAF::Reporter CAF::Object);

my $ec = LC::Exception::Context->new->will_store_all;

=pod

=head1 NAME

CAF::Application - Common Application Framework core class

=head1 SYNOPSIS


  package example;
  use CAF::Application;
  use LC::Exception qw (SUCCESS throw_error);
  use strict;
  use vars (@ISA);
  @ISA= qw (CAF::Application);

  <extend/overwrite default methods here...>


  # Main loop
  package main;
  use LC::Exception qw (SUCCESS throw_error);

  use strict;
  use vars ($this_app %SIG);

  unless ($this_app = example->new($0,@ARGV)) {
    throw_error (...);
  }

  $this_app->report("Hello");
  ...


=head1 INHERITANCE

  CAF::Object

=head1 DESCRIPTION

B<CAF::Application> is the core class which provides command line and
configuration file parsing, and general application methods.

Applications can extend or overwrite the default methods.



=over

=cut
  
#------------------------------------------------------------
#                      Public Methods/Functions
#------------------------------------------------------------

=pod

=back

=head2 Public methods

=over 4

=item name():string

Return the application name (basename)

=cut

sub name ($) {
  my $self = shift;
  return $self->{'NAME'};
}


=pod

=item version():string

Returns the version number as defined in $self->{'VERSION'}, or
<unknown> if not defined.

=cut

sub version ($) {
  my $self = shift;
  return defined $self->{'VERSION'} ? $self->{'VERSION'} : '<unknown>';
}

=pod

=item hostname():string

Returns the machine's hostname.

=cut


sub hostname ($) {
  my $self = shift;
  return $self->{'HOSTNAME'};
}

=pod

=item username():string

Returns the name of the user.

=cut

sub username {
  my $self = shift;
  return $self->{'USERNAME'};
}


=pod

=item option($opt):scalar|undef

prints give back the option value coming from the command line and/or
configuration file. Scalar can be a string, or a reference to a hash
or an array containing the option's value. option() is a wrapper
on top of AppConfig->get($opt).

=cut


sub option ($$) {
  my ($self,$opt) = @_;

  return $self->{'CONFIG'}->get($opt);
}




=pod

=item show_usage(): boolean

Prints the usage message of the command based on options and help text.

=cut

sub show_usage () {
  my $self = shift;
  # show the version
  $self->show_version();
  # show usage
  print $self->{'USAGE'}."\n";
  print "The following options are available:\n\n";
  #
  # now loop over the options, print out aliases, default values
  # and types, and help text.
  #
  my $opt;
  foreach $opt (sort keys %{$self->{'CFHELP'}}) {
    # format is (option|alias1|alias2|..(!|((:|=)(s|f|i)(@|%)?))?)
    # take everything into one regexp as faster.
    #
    if ($opt =~ /([^=:!|]+)((\|([^=:!|]+))*)(!|((:|=)(s|f|i)(@|%)?))?/) {
      my ($optname,$aliases,$spec,$optional,$atom,$vect)=($1,$2,$5,$7,$8,$9);
      my $str=' --'.$optname;
      if (defined $aliases) {
        $aliases =~ s%\|%, --%g;
        $str .= $aliases;
      }
      unless (!defined $spec || $spec eq '!') {
        # not a simple flag.
        if ($atom eq 's') {
          $str .='  <string>';
        } elsif ($atom eq 'f'){
          $str .='  <float>';
        } elsif ($atom eq 'i'){
          $str .='  <integer>';
        }
        if (defined $vect) {
          if ($vect eq '@') {
            $str .= ' (list)';
          } elsif ($vect eq '%') {
            $str .= ' (hash)';
          }
        }
        if ($optional eq ':') {
          $str .= ' (optional value)';
        }
        # any default value?
        my $default=$self->{'CONFIG'}->get($optname);
        if (defined $default) {
          if (ref($default) eq '') { #string
            $str .="\n\t(default: '".$default."')";
          } elsif (ref($default) eq 'ARRAY' && scalar (@$default)) {
            $str .="\n\t(default: '".join(', ',@{$default})."')";
          } elsif (ref($default) eq 'HASH' && scalar (keys (%$default))) {
            $str .="\n\t(default:\n";
            foreach (keys(%$default)) {
              $str .="\t\t$_ -> ".$default->{$_}."\n";
            }
            $str .="\t)";
          }
        }
      }
      # add help text.
      $str .= "\n\t".$self->{'CFHELP'}{$opt}."\n";
      print $str;
    } else {
      throw_error("cannot parse option: $opt");
      return undef;
    }
  }
  print "\n"; # nice last empty line
  return SUCCESS;
}


=pod

=item show_version(): boolean

prints the version number of the Application.

=cut



sub show_version () {
  my $self = shift;
  print "This is ",$self->name()," version ",$self->version(),"\n";
  return SUCCESS;
}


=pod

=item app_options(): ref(array)

to be overloaded by the application with application specific options.

This function has to return a reference to an array. 
Every element in the array must be a reference to a hash with the
following structure:

 NAME    => option name specification in the Getopt::Long(3pm) format
            "name|altname1|altname2|..[argument_type]"
 DEFAULT => [optional] default value (string). If not specified: undef
 HELP    => help text (string)

example:

 push(@array, {NAME =>'M|myoption=s' ,
               DEFAULT=>'defaultvalue',
               HELP=>'do somewhat on something'});

 return \@array;

see also _app_default_options()

=cut

sub app_options () {
# to be implemented by derived class, if required
  return [()];
}



=pod 

=back

=head2 Private methods

=over 4

=item _initialize

Initialize the Application.

=cut

sub _initialize ($$@) {
  my ($self,$command,@argv) = @_;

  $self->{'NAME'} = basename($command);

  # who is the user
  $self->{'USERNAME'} = (getpwuid($<))[0] || getlogin || undef;
  # name of machine
  my ($sysname,$nodename,$release,$version,$machine) = POSIX::uname();
  $self->{'HOSTNAME'} = $nodename;

  #
  # instantiate default configuration options and values,
  # as given by Application.pm and/or the Application,
  # and pass them to AppConfig.
  #
  # defaults: no option arguments,
  #           expand internal vars in cf file, but scream if
  #             an embedded variable is not defined (EXPAND_WARN)
  #           option values are 'undef'
  #
  $self->{'CONFIG'}= AppConfig->new({
                                    PEDANTIC => 1, # really needed?
                                    CASE => 0,
                                    GLOBAL => {
                                            DEFAULT  => undef,
                                            ARGCOUNT => ARGCOUNT_NONE,
                                            EXPAND   => EXPAND_VAR|EXPAND_WARN
                                              }
                                    });
  #
  # add application-specific options
  #
  unless ($self->_add_options()) {
    throw_error('Cannot add options');
    return undef;
  }
  #
  # check if we have a config file to read or a --help request.
  # parse it 'by hand' instead of using AppConfig twice
  # for cmd line parsing
  #
  my $help_request=0;
  my $configfile=undef;
  my @args_tmp = @argv;
  my $arg;
  while ($arg=shift(@args_tmp)) {
    $help_request=1 if (($arg =~ m%^(-|--)help$%));
    $configfile = shift (@args_tmp) if ($arg =~ m%^(--cfgfile)$%);
    $configfile = $2 if ($arg =~ m%^(--cfgfile=(\S+))$%);
  }

  my %confvar=$self->{'CONFIG'}->varlist('^cfgfile$');
  if (exists $confvar{'cfgfile'}) {
    $configfile=$self->option("cfgfile") unless (defined $configfile);

    #
    if (defined $configfile) {
      unless (-e $configfile) {
        print STDERR "Warning: cannot read config file: $configfile, dropping.\n";
      } else {
        # read conf file options.
        # Note that a 'cfgfile' option doesn't make
        # any sense inside the cfgfile ;-)
        unless ($self->{'CONFIG'}->file($configfile)) {
          # exit if something is wrong according to AppConfig.
          print STDERR "Problems parsing configuration file ".$configfile."\n";
          exit(-1);
          #        throw_error('problems reading configuration file: '.$configfile);
          #        return undef;
        }
      }
    }
  }
  #
  # if there was a request for --help, go for it before
  # getting command line opt values (for getting the current
  # default values before overwriting them with cmd line opts)
  #
  if ($help_request) {
    $self->show_usage();
    exit (0);
  }
  #
  # now read in cmd line options, which always have highest priority.
  # (uses Getopt::Long)
  #
  unless ($self->{'CONFIG'}->getopt(\@argv)) {
    # exit if something is wrong according to AppConfig.
    # print STDERR "problems reading command line\n";
    exit(-1);
    # throw_error('problems reading command line options');
    # return undef;
  }

  #
  # now we have all options available!
  # Process now common options.
  #

  #
  # user asks for --version
  #
  if ($self->option('version')) {
    $self->show_version();
    exit (0);
  }

  #
  # setup Reporter: verbose, quiet, debug
  #
  my $facility = undef;
  my %vl = $self->{'CONFIG'}->varlist(".*");
  if (exists $vl{'facility'}) {
    $facility = $self->option('facility');
  }

  $self->setup_reporter($self->option('debug'),
                        $self->option('quiet'),
                        $self->option('verbose'),
                        $facility);

  #
  # initialize log file if any.
  #

  my %logvar=$self->{'CONFIG'}->varlist('^logfile$');
  if (exists $logvar{'logfile'}) {
    my $logfile=$self->option("logfile");
    if (defined $logfile) {
      # log requested on $logfile. Try to instantiate it and attach
      # it to the reporter.
      my $logflags='w';
      $logflags  = 'a' if (defined $self->{'LOG_APPEND'});
      $logflags .= 't' if (defined $self->{'LOG_TSTAMP'});

      $self->{'LOG'} = CAF::Log->new($logfile, $logflags);
      unless (defined $self->{'LOG'}) {
        $ec->rethrow_error;
        return undef;
        #
        # the log file is to be activated inside the
        # application itself using
        # $self->set_report_logfile($self->{'LOG'})
        #
      }
    }
  }

  # all done!
  return SUCCESS;
}





=pod

=item _app_default_options

This method specifies a number of default options, with the
same format as app_options. The options are:

  debug <debuglevel> : sets debug level (1 to 5)
  help               : prints out help message
  quiet              : no output
  verbose            : verbose output
  version            : print out version number & exit

The 'noaction', 'cfgfile' and 'logfile' options are not enabled
by default but recognized (they have to be added to the application
specific code - see the 'example' file):

  noaction           : execute no operations
  cfgfile <string>  : use configuration file <string>
  logfile  <string>  : use log file <string>

=cut


sub _app_default_options () {

  my @app_array=(
                 {NAME =>'help',
                  HELP =>'displays this help message.'},
                 {NAME =>'version',
                  HELP =>'prints current version and exits.'},
                 {NAME =>'verbose',
                  HELP =>'print more details on operations.'},
                 {NAME =>'debug=i' ,
                  HELP =>'set the debugging level to <1..5>.'},
                 {NAME =>'quiet',
                  HELP =>'suppress application output to stdout.'}#,
#                 {NAME =>'noaction',
#                  HELP =>'do not actually perform operations.'},
#                 {NAME =>'cfgfile=s',
#                  HELP =>'configuration file name'}
                );

  return \@app_array;
}


=pod

=item _add_options

add options coming from _app_default_options() and app_options()

=cut


sub _add_options ($) {
  my $self=shift;


  my $opt_default_ref=$self->_app_default_options();
  my $opt_app_ref = $self->app_options();

  my @opts=@{$opt_default_ref};
  push (@opts,@{$opt_app_ref});

  my $opt;
  foreach $opt (@opts) {
    my $default=undef;
    $default=$opt->{'DEFAULT'} if (defined $opt->{'DEFAULT'});

#
# AppConfig doesn't return anything sensible - if an error is found,
# it just uses a 'warn'. A user defined function should be used here
# to trap the error..
#

    $self->{'CONFIG'}->define($opt->{'NAME'},{DEFAULT=>$default});

#    unless ($self->{'CONFIG'}->define($opt->{'NAME'},{DEFAULT=>$default})) {
#      throw_error("error in application configuration: ".$opt->{'NAME'});
#      return undef;
#    }
    #
    # setup help text for --help
    #
    $self->{'CFHELP'}{$opt->{'NAME'}}=$opt->{'HELP'};

    # possible extension: don't allow options starting with 'no..'
  }
  return SUCCESS;
}


END {
    # report all stored warnings
    foreach my $warning ($ec->warnings) {
        warn("[WARN] $warning");
    }
    $ec->clear_warnings;
}


=pod

=back

=cut

#------------------------------------------------------------
#                      Other doc
#------------------------------------------------------------

=pod

=head1 SEE ALSO

CAF::Object, LC::Exception, CAF::Reporter

=head1 AUTHORS

German Cancio <German.Cancio@cern.ch>

=head1 VERSION

$Id: Application.pm,v 1.11 2006/08/18 17:06:53 poleggi Exp $

=cut

1; ## END ##
