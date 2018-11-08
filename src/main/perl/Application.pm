#${PMpre} CAF::Application${PMpost}

use CAF::Reporter;
use LC::Exception qw (SUCCESS throw_error);
use AppConfig qw (:argcount :expand);
use CAF::Object;
use CAF::Log;
use File::Basename;
use POSIX;

use parent qw(CAF::Reporter CAF::Object Exporter);

use Readonly;
Readonly our $OPTION_CFGFILE => 'cfgfile';

our @EXPORT    = qw();
our @EXPORT_OK = qw($OPTION_CFGFILE);

my $ec = LC::Exception::Context->new->will_store_all;

=pod

=head1 NAME

CAF::Application - Common Application Framework core class

=head1 SYNOPSIS


  package example;
  use strict;
  use warnings;
  use LC::Exception qw (SUCCESS throw_error);
  use parent qw(CAF::Application);

  <extend/overwrite default methods here...>


  # Main loop
  package main;
  use strict;
  use warnings;
  use LC::Exception qw (SUCCESS throw_error);

  use vars ($this_app %SIG);

  unless ($this_app = example->new($0,@ARGV)) {
    throw_error (...);
  }

  $this_app->report("Hello");
  ...


=head1 DESCRIPTION

B<CAF::Application> is the core class which provides command line and
configuration file parsing, and general application methods.

Applications can extend or overwrite the default methods.

=head2 Public methods

=over 4

=item name(): string

Return the application name (basename)

=cut

sub name
{
    my $self = shift;
    return $self->{'NAME'};
}

=pod

=item version(): string

Returns the version number as defined in C<< $self->{'VERSION'} >>, or
C<< <unknown> >> if not defined.

=cut

sub version
{
    my $self = shift;
    return defined $self->{'VERSION'} ? $self->{'VERSION'} : '<unknown>';
}

=pod

=item hostname(): string

Returns the machine's hostname.

=cut


sub hostname
{
    my $self = shift;
    return $self->{'HOSTNAME'};
}

=pod

=item username(): string

Returns the name of the user.

=cut

sub username
{
    my $self = shift;
    return $self->{'USERNAME'};
}

=pod

=item option_exists($opt): boolean

Returns true if the option exists, false otherwhise. Option can be
defined either in the application configuration file or on the
command line (based on C<AppConfig> module).

=cut

# Check if a configuration option exists
sub option_exists
{
    my ($self, $option) = @_;
    return $self->{CONFIG}->_exists($option);
}

=pod

=item option($opt): scalar|undef

Returns the option value coming from the command line and/or
configuration file. Scalar can be a string, or a reference to a hash
or an array containing the option's value. C<option()> is a wrapper
on top of C<< AppConfig->get($opt) >>.

If the option doesn't exist, returns C<undef>, except if the C<default>
argument has been specified: in this case this value is returned but
the option remains undefined.

=cut

sub option
{
    my ($self, $opt, $default) = @_;

    if ( $self->option_exists($opt) ) {
        return $self->{'CONFIG'}->get($opt);
    }

    return $default;
}

=pod

=item set_option($opt, $val): SUCCESS

Defines an option and sets its value. If the option was previously
defined, its value is overwritten. This is a wrapper over C<AppConfig> 
methods to hide the internal implementation of a C<CAF::Application>.

This method always returns SUCCESS.

=cut

sub set_option
{
    my ($self, $opt, $val) = @_;

    $self->{'CONFIG'}->define($opt);
    $self->{'CONFIG'}->set($opt, $val);

    return SUCCESS;
}

=pod

=item show_usage(): boolean

Prints the usage message of the command based on options and help text.

=cut

sub show_usage
{
    my $self = shift;

    # show the version
    $self->show_version();

    # show usage
    print $self->{'USAGE'}."\n";
    print "The following options are available:\n\n";

    # now loop over the options, print out aliases, default values
    # and types, and help text.
    foreach my $opt (sort keys %{$self->{'CFHELP'}}) {
        # format is (option|alias1|alias2|..(!|((:|=)(s|f|i)(@|%)?))?)
        # take everything into one regexp as faster.
        if ($opt =~ /([^=:!|]+)((\|([^=:!|]+))*)(!|((:|=)(s|f|i)(@|%)?))?/) {
            my ($optname,$aliases,$spec,$optional,$atom,$vect) = ($1,$2,$5,$7,$8,$9);
            my $str = ' --'.$optname;
            if (defined $aliases) {
                $aliases =~ s%\|%, --%g;
                $str .= $aliases;
            }
            unless (!defined $spec || $spec eq '!') {
                # not a simple flag.
                if ($atom eq 's') {
                    $str .= '  <string>';
                } elsif ($atom eq 'f'){
                    $str .= '  <float>';
                } elsif ($atom eq 'i'){
                    $str .= '  <integer>';
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
                my $default = $self->{'CONFIG'}->get($optname);
                if (defined $default) {
                    if (ref($default) eq '') { #string
                        $str .= "\n\t(default: '".$default."')";
                    } elsif (ref($default) eq 'ARRAY' && scalar (@$default)) {
                        $str .= "\n\t(default: '".join(', ',@{$default})."')";
                    } elsif (ref($default) eq 'HASH' && scalar (keys (%$default))) {
                        $str .= "\n\t(default:\n";
                        foreach (keys(%$default)) {
                            $str .= "\t\t$_ -> ".$default->{$_}."\n";
                        }
                        $str .= "\t)";
                    }
                }
            }

            # add help text.
            $str .= "\n\t".$self->{'CFHELP'}{$opt}."\n";
            print $str;
        } else {
            throw_error("cannot parse option: $opt");
            return;
        }
    }
    print "\n"; # nice last empty line
    return SUCCESS;
}

=pod

=item show_version(): boolean

prints the version number of the Application.

=cut

sub show_version
{
    my $self = shift;
    print "This is ", $self->name(), " version ", $self->version(), "\n";
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

sub app_options
{
    # to be implemented by derived class, if required
    return [()];
}

=pod

=back

=head2 Private methods

=over 4

=item _initialize

Initialize the Application.

Arguments

=over

=item C<$command>

Name of the script/command/... (typically C<$0>).

=item Remaining arguments C<@argv>

Typically this is the perl builtin variable C<@ARGV>,
but can be any array of options/arguments,
or a single arrayref (in which case all elements
of the arrayref are handled as options/arguments).

Any arguments that are not handled by the options,
can be retrieved either via C<@ARGV> or by passing
an arrayref holding the options/arguments.
In these 2 cases, the contents is modified,
removing all handled options, leaving the
non-option arguments in place.
(In particular, using a regular array
will leave the original array unmodified).

=back

=cut

sub _initialize
{
    my ($self, $command, @argv) = @_;

    $self->{'NAME'} = basename($command);

    my $argvref;
    if ((scalar @argv == 1) && (ref($argv[0]) eq 'ARRAY')) {
        $self->debug(4, 'argv array handled as array reference');
        $argvref = $argv[0];
    } else {
        $argvref = \@argv;
    }

    # who is the user
    $self->{'USERNAME'} = (getpwuid($<))[0] || getlogin || undef;
    # name of machine
    my ($sysname,$nodename,$release,$version,$machine) = POSIX::uname();
    $self->{'HOSTNAME'} = $nodename;

    # instantiate default configuration options and values,
    # as given by Application.pm and/or the Application,
    # and pass them to AppConfig.
    #
    # defaults: no option arguments,
    #           expand internal vars in cf file, but scream if
    #             an embedded variable is not defined (EXPAND_WARN)
    #           option values are 'undef'
    $self->{'CONFIG'}= AppConfig->new({
        PEDANTIC => 1, # really needed?
        CASE => 0,
        GLOBAL => {
            DEFAULT  => undef,
            ARGCOUNT => ARGCOUNT_NONE,
            EXPAND   => EXPAND_VAR|EXPAND_WARN
        }
    });

    # initialise predefined options
    $self->{'CONFIG'}->define($OPTION_CFGFILE, {ARGCOUNT => ARGCOUNT_ONE});

    # add application-specific options
    unless ($self->_add_options()) {
        throw_error('Cannot add options');
        return;
    }

    # check if we have a config file to read or a --help request.
    # parse it 'by hand' instead of using AppConfig twice
    # for cmd line parsing
    my $help_request = 0;
    my $configfile = undef;
    my @args_tmp = @$argvref;
    my $arg;

    my $cfgfile_value_pattern = "^--?$OPTION_CFGFILE(?:=(\\S+))?\$";
    while ($arg = shift(@args_tmp)) {
        $help_request=1 if (($arg =~ m/^--?help$/));

        if ($arg =~ m/$cfgfile_value_pattern/) {
            if (defined($1)) {
                # format --cfgfile=path/to/file
                $configfile = $1;
            } else {
                # format --cfgfile path/to/file
                $configfile = shift (@args_tmp);
            }
        }
    }

    # Read default if configfile is not set via commandline
    $configfile = $self->option($OPTION_CFGFILE) if (! defined($configfile));

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
            }
        }
    }

    # if there was a request for --help, go for it before
    # getting command line opt values (for getting the current
    # default values before overwriting them with cmd line opts)
    if ($help_request) {
        $self->show_usage();
        exit (0);
    }

    # now read in cmd line options, which always have highest priority.
    # (uses Getopt::Long)
    unless ($self->{'CONFIG'}->getopt($argvref)) {
        # exit if something is wrong according to AppConfig.
        exit(-1);
    }

    # now we have all options available!
    # Process now common options.

    # user asks for --version
    if ($self->option('version')) {
        $self->show_version();
        exit (0);
    }

    # setup Reporter: verbose, quiet, debug
    my $facility = undef;
    my %vl = $self->{'CONFIG'}->varlist(".*");
    if (exists $vl{'facility'}) {
        $facility = $self->option('facility');
    }

    $self->config_reporter(
        debuglvl => $self->option('debug'),
        quiet => $self->option('quiet'),
        verbose => $self->option('verbose'),
        facility => $facility
        );

    # initialize log file if any.
    # the log file is to be activated inside the
    # application itself using
    #     $self->config_reporter(logfile => $self->{'LOG'})
    my %logvar = $self->{'CONFIG'}->varlist('^logfile$');
    if (exists $logvar{'logfile'}) {
        my $logfile = $self->option("logfile");
        if (defined $logfile) {
            # log requested on $logfile. Try to instantiate it and attach
            # it to the reporter.
            my $logflags = 'w';
            $logflags  = 'a' if (defined $self->{'LOG_APPEND'});
            $logflags .= 't' if (defined $self->{'LOG_TSTAMP'});
            $logflags .= 'p' if (defined $self->{'LOG_PROCID'});

            $self->{'LOG'} = CAF::Log->new($logfile, $logflags);
            unless (defined $self->{'LOG'}) {
                $ec->rethrow_error;
                return;
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

sub _app_default_options
{

    my @app_array = (
        {
            NAME => 'help',
            HELP => 'displays this help message.',
        },
        {
            NAME => 'version',
            HELP => 'prints current version and exits.',
        },
        {
            NAME => 'verbose',
            HELP => 'print more details on operations.',
        },
        {
            NAME => 'debug=i',
            HELP => 'set the debugging level to <1..5>.',
        },
        {
            NAME => 'quiet',
            HELP =>'suppress application output to stdout.',
        },
    );

    return \@app_array;
}


=pod

=item _add_options

add options coming from _app_default_options() and app_options()

=cut

sub _add_options
{
    my $self=shift;

    my $opt_default_ref = $self->_app_default_options();
    my $opt_app_ref = $self->app_options();

    my @opts = @{$opt_default_ref};
    push (@opts, @{$opt_app_ref});

    foreach my $opt (@opts) {
        my $default;
        $default = $opt->{'DEFAULT'} if (defined $opt->{'DEFAULT'});

        # AppConfig doesn't return anything sensible - if an error is found,
        # it just uses a 'warn'. A user defined function should be used here
        # to trap the error..

        $self->{'CONFIG'}->define(
            $opt->{'NAME'},
            {
                DEFAULT => $default,
            });

        # setup help text for --help
        $self->{'CFHELP'}{$opt->{'NAME'}}=$opt->{'HELP'};

        # possible extension: don't allow options starting with 'no..'
    }
    return SUCCESS;
}


END {
    # report all stored warnings
    # TODO why not errors too?
    foreach my $warning ($ec->warnings) {
        warn("[WARN] $warning");
    }
    $ec->clear_warnings;
}


=pod

=back

=cut

1;
