#${PMpre} CAF::Process${PMpost}

use parent qw(CAF::Object);

use LC::Exception qw (SUCCESS throw_error);
use LC::Process;

use File::Which;
use File::Basename;

use overload ('""' => 'stringify_command');
use Readonly;

Readonly::Hash my %LC_PROCESS_DISPATCH => {
    output => \&LC::Process::output,
    toutput => \&LC::Process::toutput,
    run => \&LC::Process::run,
    trun => \&LC::Process::trun,
    execute => \&LC::Process::execute,
};


=pod

=head1 NAME

CAF::Process - Class for running commands in CAF applications

=head1 SYNOPSIS

    use CAF::Process;
    my $proc = CAF::Process->new ([qw (my command)], log => $self);
    $proc->pushargs (qw (more arguments));
    my $output = $proc->output();
    $proc->execute();

=head1 DESCRIPTION

This class provides a convenient wrapper to LC::Process
functions. Commands are logged at the verbose level.

All these methods return the return value of their LC::Process
equivalent. This is different from the command's exit status, which is
stored in C<$?>.

Please use these functions, and B<do not> use C<``>, C<qx//> or
C<system>. These functions won't spawn a subshell, and thus are more
secure.

=cut

=head2 Private methods

=over

=item C<_initialize>

Initialize the process object. Arguments:

=over

=item C<$command>

A reference to an array with the command and its arguments.

=item C<%opts>

A hash with the command options:

=over

=item C<log>

The log object. If not supplied, no logging will be performed.

=item C<timeout>

Maximum execution time, in seconds, for the command. If it's too slow
it will be killed.

=item C<pid>

Reference to a scalar that will hold the child's PID.

=item C<stdin>

Data to be passed to the child's stdin

=item C<stdout>

Reference to a scalar that will have child's stdout

=item C<stderr>

Reference to a scalar that will hold the child's stderr.

=item C<keeps_state>

A boolean specifying whether the command respects the current system
state or not. A command that C<keeps_state> will be executed,
regardless of any value for C<NoAction>.

By default, commands modify the state and thus C<keeps_state> is
false.

=item C<sensitive>

A boolean, hashref or functionref specifying whether the arguments contain
sensitive information (like passwords).

If C<sensitive> is true, the commandline will not be reported
(by default when C<log> option is used, the commandline is reported
with verbose level).

If C<sensitive> is a hash reference, a basic search (key) and replace (value) is performed.
The keys and values are not interpreted as regexp patterns. The order of the search and
replace is determined by the sorted values (this gives you some control over the order).
Be aware that all occurences are replaced, and when e.g. weak passwords are used,
it might reveal the password by replacing other parts of the commandline
(C<--password=password> might be replaced by C<--SECRET=SECRET>,
thus revealing the weak password).
Also, when a key is a substring of another key,
it will reveal (parts of) sensitive data if the order is not correct.

If C<sensitive> is a function reference, the command arrayref is passed
as only argument, and the stringified return value is reported.

    my $replace = sub {
        my $command = shift;
        return join("_", @$command);
    };

    ...

    CAF::Process->new(..., sensitive => $replace);

This does not cover command output. If the output (stdout and/or stderr) contains
sensitve information, make sure to handle it yourself via C<stdout> and/or C<stderr>
options (or by using the C<output> method).

=back

These options will only be used by the execute method.

=back

=cut

sub _initialize
{
    my ($self, $command, %opts) = @_;

    $self->{log} = $opts{log} if defined($opts{log});

    if ($opts{keeps_state}) {
        $self->debug(1, "keeps_state set");
        $self->{NoAction} = 0
    };

    $self->{sensitive} = $opts{sensitive};

    $self->{COMMAND} = $command;

    $self->setopts (%opts);

    return SUCCESS;
}


=item _sensitive_commandline

Generate the reported command line text, in particular it deals with
the C<sensitive> attribute.
When the sensitive attribute is not set, it returns C<stringify_command>.

This method does not report, only returns text.

See the description of the C<sensitive> option in C<_initialize>.

=cut

sub _sensitive_commandline
{
    my ($self) = @_;

    my $text;
    my $senstxt = "$self->{COMMAND}->[0] <sensitive>";
    my $sens = $self->{sensitive};
    if (ref($sens) eq 'CODE') {
        local $@;
        my $sensdata;
        eval {
            $sensdata = $sens->($self->{COMMAND});
        };
        if ($@) {
            # Do not report error, it might contain sensitive data
            $text = "$senstxt (sensitive function failed, contact developers)";
        } else {
            $text = "$sensdata";
        }
    } elsif (ref($sens) eq 'HASH') {
        # sort keys on value
        $text = $self->stringify_command();
        my @keys = sort { $sens->{$a} cmp $sens->{$b} } keys(%$sens);
        foreach my $key (@keys) {
            # metaquote both keys and values
            $text =~ s/\Q$key\E/\Q$sens->{$key}\E/g;
        }
    } elsif ($sens) {
        $text = $senstxt;
    } else {
        $text = $self->stringify_command();
    }
    return $text;
}

=item _LC_Process

Run C<LC::Process> C<function> with arrayref arguments C<args>.

C<noaction_value> is is the value to return with C<NoAction>.

C<msg> and C<postmsg> are used to construct log message
C<< <msg> command: <COMMAND>[ <postmsg>] >>.

=cut

sub _LC_Process
{
    my ($self, $function, $args, $noaction_value, $msg, $postmsg) = @_;

    $msg =~ s/^(\w)/Not \L$1/ if $self->noAction();
    $self->verbose("$msg command: ", $self->_sensitive_commandline(),
                   (defined($postmsg) ? " $postmsg" : ''));

    if ($self->noAction()) {
        $self->debug(1, "LC_Process in noaction mode for $function");
        $? = 0;
        return $noaction_value;
    } else {
        my $funcref = $LC_PROCESS_DISPATCH{$function};
        if (defined($funcref)) {
            return $funcref->(@$args);
        } else {
            $self->error("Unsupported LC::Process function $function");
            return;
        }
    }
}

=back

=head2 Public methods

=over

=item execute

Runs the command, with the options passed at initialization time. If
running on verbose mode, the exact command line and options are
logged.

Please, initialize the object with C<< log => '' >> if you are passing
confidential data as an argument to your command.

=back

=cut

sub execute
{
    my $self = shift;

    my @opts = ();
    foreach my $k (sort(keys (%{$self->{OPTIONS}}))) {
        push (@opts, "$k=$self->{OPTIONS}->{$k}");
    }

    return $self->_LC_Process(
        'execute',
        [$self->{COMMAND}, %{$self->{OPTIONS}}],
        0,
        "Executing",
        join (" ", "with options:", @opts),
        );
}

=over

=item output

Returns the output of the command. The output will not be logged for
security reasons.

=back

=cut

sub output
{
    my $self = shift;

    return $self->_LC_Process(
        'output',
        [@{$self->{COMMAND}}],
        '',
        "Getting output of",
        );
}

=over

=item toutput

Returns the output of the command, that will be run with the timeout
passed as an argument. The output will not be logged for security
reasons.

=back

=cut

sub toutput
{
    my ($self, $timeout) = @_;

    return $self->_LC_Process(
        'toutput',
        [$timeout, @{$self->{COMMAND}}],
        '',
        "Getting output of",
        "with $timeout seconds of timeout",
        );
}

=over

=item stream_output

Execute the commands using C<execute>, but the C<stderr> is
redirected to C<stdout>, and C<stdout> is processed with C<process>
function. The total output is aggregated and returned when finished.

Extra option is the process C<mode>. By default (or value C<undef>),
the new output is passed to C<process>. With mode C<line>, C<process>
is called for each line of output (i.e. separated by newline), and
the remainder of the output when the process is finished.

Another option are the process C<arguments>. This is a reference to the
array of arguments passed to the C<process> function.
The arguments are passed before the output to the C<process>: e.g.
if C<< arguments =\> [qw(a b)] >> is used, the C<process> function is
called like C<process(a,b,$newoutput)> (with C<$newoutput> the
new streamed output)

Example usage: during a C<yum install>, you want to stop the yum process
when an error message is detected.

    sub act {
        my ($self, $proc, $message) = @_;
        if ($message =~ m/error/) {
            $self->error("Error encountered, stopping process: $message");
            $proc->stop;
        }
    }

    $self->info("Going to start yum");
    my $p = CAF::Process->new([qw(yum install error)], input => 'init');
    $p->stream_output(\&act, mode => line, arguments => [$self, $p]);

=back

=cut

sub stream_output
{
    my ($self, $process, %opts) = @_;

    my ($mode, @process_args);
    $mode = $opts{mode} if exists($opts{mode});
    @process_args = @{$opts{arguments}} if exists($opts{arguments});

    my @total_out = ();
    my $last = 0;
    my $remainder = "";

    # Define this sub here. Makes no sense to define it outside this sub
    # Use anonymous sub to avoid "Variable will not stay shared" warnings
    my $stdout_func = sub  {
        my ($bufout) = @_;
        my $diff = substr($bufout, $last);
        if (defined($mode) && $mode eq 'line') {
            # split $diff in newlines
            # last part is empty? or has no newline, i.e. remainder
            my @lines = split(/\n/, $diff, -1); # keep trailing empty
            $remainder = pop @lines; # always possible
            # all others, print them
            foreach my $line (@lines) {
                $process->(@process_args, $line);
            }
        } else {
            # no remainder, leave it empty string
            $process->(@process_args, $diff);
        }
        $last = length($bufout) - length($remainder);
        push(@total_out,substr($diff, 0, length($diff) - length($remainder)));

        return 0;
    };

    $self->{OPTIONS}->{stderr} = 'stdout';
    $self->{OPTIONS}->{stdout} = $stdout_func;

    my $execute_res = $self->execute();

    # not called with empty remainder
    if ($remainder) {
        $process->(@process_args, $remainder);
        push(@total_out, $remainder);
    };

    return(join("", @total_out));
}

=over

=item run

Runs the command.

=back

=cut

sub run
{
    my $self = shift;

    return $self->_LC_Process(
        'run',
        [@{$self->{COMMAND}}],
        0,
        "Running the",
        );
}

=over

=item trun

Runs the command with $timeout seconds of timeout.

=back

=cut

sub trun
{
    my ($self, $timeout) = @_;

    return $self->_LC_Process(
        'trun',
        [$timeout, @{$self->{COMMAND}}],
        0,
        "Running the",
        "with $timeout seconds of timeout",
        );
}

=over

=item pushargs

Appends the arguments to the list of command arguments

=back

=cut

sub pushargs
{
    my ($self, @args) = @_;

    push (@{$self->{COMMAND}}, @args);
}

=over

=item setopts

Sets the hash of options passed to the options for the command

=back

=cut

sub setopts
{
    my ($self, %opts) = @_;

    foreach my $i (qw(timeout stdin stderr stdout shell)) {
        $self->{OPTIONS}->{$i} = $opts{$i} if exists($opts{$i});
    }

    # Initialize stdout and stderr if they exist. Otherwise, NoAction
    # runs will spill plenty of spurious uninitialized warnings.
    foreach my $i (qw(stdout stderr)) {
        if (exists($self->{OPTIONS}->{$i}) && ref($self->{OPTIONS}->{$i}) &&
            !defined(${$self->{OPTIONS}->{$i}})) {
            ${$self->{OPTIONS}->{$i}} = "";
        }
    }
}

=over

=item stringify_command

Return the command and its arguments as a space separated string.

=back

=cut

sub stringify_command
{
    my ($self) = @_;
    return join(" ", @{$self->{COMMAND}});
}

=over

=item get_command

Return the reference to the array with the command and its arguments.

=back

=cut

sub get_command
{
    my ($self) = @_;
    return $self->{COMMAND};
}


=over

=item get_executable

Return the executable (i.e. the first element of the command).

=back

=cut

sub get_executable
{
    my ($self) = @_;

    return ${$self->{COMMAND}}[0];

}


# Tests if a filename is executable. However, using -x
# makes this not mockable, and thus this test is separated
# from C<is_executable> in the C<_test_executable> private
# method for unittesting.
sub _test_executable
{
    my ($self, $executable) = @_;
    return -x $executable;
}

=over

=item is_executable

Checks if the first element of the
array with the command and its arguments, is executable.

It returns the result of the C<-x> test on the filename
(or C<undef> if filename can't be resolved).

If the filename is equal to the C<basename>, then the
filename to test is resolved using the
C<File::Which::which> method.
(Use C<./script> if you want to check a script in the
current working directory).

=back

=cut

sub is_executable
{
    my ($self) = @_;

    my $executable = $self->get_executable();

    if ($executable eq basename($executable)) {
        my $executable_path = which($executable);
        if (defined($executable_path)) {
            $self->debug (1, "Executable $executable resolved via which to $executable_path");
            $executable = $executable_path;
        } else {
            $self->debug (1, "Executable $executable couldn't be resolved via which");
            return;
        }
    }

    my $res = $self->_test_executable($executable);
    $self->debug (1, "Executable $executable is ", $res ? "": "not " , "executable");
    return $res;
}

=over

=item execute_if_exists

Execute after verifying the executable (i.e. the first
element of the command) exists and is executable.

If this is not the case the method returns 1.

=back

=cut


sub execute_if_exists
{
    my ($self) = @_;

    if ($self->is_executable()) {
        return $self->execute();
    } else {
        $self->verbose("Command ".$self->get_executable()." not found or not executable");
        return 1;
    }
}


1;

=pod

=head1 COMMON USE CASES

On the next examples, no log is used. If you want your component to
log the command, just add C<< log => $self >> to the object creation.

=head2 Running a command

First, create the command:

    my $proc = CAF::Process->new (["ls", "-lh"]);

Then, choose amongst:

    $proc->run();
    $proc->execute();

=head2 Emulating backticks to get a command's output

Create the command:

    my $proc = CAF::Process->new (["ls", "-lh"]);

And get the output:

    my $output = $proc->output();

=head2 Piping into a command's stdin

Create the contents to be piped:

    my $contents = "Hello, world";

Create the command, specifying C<$contents> as the input, and
C<execute> it:

    my $proc = CAF::Process->new (["cat", "-"], stdin => $contents);
    $proc->execute();

=head2 Piping in and out

Suppose we want a bi-directional pipe: we provide the command's stdin,
and need to get its output and error:

    my ($stdin, $stdout, $stderr) = ("Hello, world", undef, undef);
    my $proc = CAF::Process->new (["cat", "-"], stdin => $stdin,
                                  stdout => \$stdout
                                  stderr => \$stderr);
    $proc->execute();

And we'll have the command's standard output and error on $stdout and
$stderr.

=head2 Creating the command dynamically

Suppose you want to add options to your command, dynamically:

    my $proc = CAF::Process->new (["ls", "-l"]);
    $proc->pushargs ("-a", "-h");
    if ($my_expression) {
        $proc->pushargs ("-S");
    }

    # Runs ls -l -a -h -S
    $proc->run();

=head2 Subshells

Okay, you B<really> want them. You can't live without them. You found
some obscure case that really needs a shell. Here is how to get
it. But please, don't use it without a B<good> reason:

    my $cmd = CAF::Process->new(["ls -lh|wc -l"], log => $self,
                                 shell => 1);
    $cmd->execute();

It will only work with the C<execute> method.

=cut
