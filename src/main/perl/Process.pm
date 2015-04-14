# ${license-info}
# ${developer-info
# ${author-info}
# ${build-info}
#
#
# CAF::Process class
# Written by Luis Fernando MuÃ±oz MejÃ­as <mejias@delta.ft.uam.es>

package CAF::Process;

use strict;
use warnings;
use LC::Exception qw (SUCCESS throw_error);
use LC::Process;
use CAF::Object;
use File::Which;
use File::Basename;

use overload ('""' => 'stringify_command');

our @ISA = qw (CAF::Object);

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
stored in $?.

Please use these functions, and B<do not> use C<``> or
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

=back

These options will only be used by the execute method.

=back

=back

=cut

sub _initialize
{
    my ($self, $command, %opts) = @_;

    if (exists $opts{log}) {
        if ($opts{log}) {
            $self->{log} = $opts{log};
        }
    }


    $self->{NoAction} = 0 if $opts{keeps_state};

    $self->{COMMAND} = $command;

    $self->setopts (%opts);

    return SUCCESS;
}

=head2 Public methods

=over

=item execute

Runs the command, with the options passed at initialization time. If
running on verbose mode, the exact command line and options are
logged.

Please, initialize the object with C<log => ''> if you are passing
confidential data as an argument to your command.

=back

=cut

sub execute
{
    my $self = shift;

    my $na = "E";
    if ($self->noAction()) {
        $na = "Not e";
    }
    if ($self->{log}) {
        $self->{log}->verbose (join (" ",
                    "${na}xecuting command:", @{$self->{COMMAND}}));
        my @opts = ();
        foreach my $k (sort(keys (%{$self->{OPTIONS}}))) {
            push (@opts, "$k=$self->{OPTIONS}->{$k}");
        }
        $self->{log}->verbose (join (" ", "Command options:", @opts));
    }
    if ($self->noAction()) {
        return 0;
    }
    return LC::Process::execute ($self->{COMMAND}, %{$self->{OPTIONS}});
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

    $self->{log}->verbose (join(" ", "Getting output of command:",
				@{$self->{COMMAND}}))
	if $self->{log};

    if ($self->noAction()) {
	return "";
    }

    return LC::Process::output (@{$self->{COMMAND}});
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

    $self->{log}->verbose (join (" ", "Returning the output of command:|",
				 @{$self->{COMMAND}},
				 "|with $timeout seconds of timeout"))
	if $self->{log};

    if ($self->noAction()) {
	return "";
    }
    return LC::Process::toutput ($timeout, @{$self->{COMMAND}});
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
if C<arguments =\> [qw(a b)]> is used, the C<process> function is 
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

    $self->{log}->verbose (join (" ", "Running the command:",
				 @{$self->{COMMAND}}))
	if $self->{log};
    if ($self->noAction()) {
	 return 0;
    }
    return LC::Process::run (@{$self->{COMMAND}});
}

=over

=item trun

Runs the command with $timeout seconds of timeout.

=back

=cut

sub trun
{
    my ($self, $timeout) = @_;

    $self->{log}->verbose (join (" ", "Running command:|",
				 @{$self->{COMMAND}},
				 "|with $timeout seconds of timeout"))
	if $self->{log};

    if ($self->noAction()) {
	 return 0;
    }

    return LC::Process::trun ($timeout, @{$self->{COMMAND}});
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
            $self->{log}->debug (1, "Executable $executable resolved via which to $executable_path") 
                if $self->{log};
            $executable = $executable_path;
        } else {
            $self->{log}->debug (1, "Executable $executable couldn't be resolved via which")
                if $self->{log};
            return;
        }
    }

    my $res = $self->_test_executable($executable);
    $self->{log}->debug (1, "Executable $executable is ", $res ? "": "not " , "executable")
        if $self->{log};
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
        $self->{log}->verbose("Command ".$self->get_executable()." not found or not executable")
            if $self->{log};
        return 1;
    }
}


1;

=pod

=head1 COMMON USE CASES

On the next examples, no log is used. If you want your component to
log the command, just add log => $self to the object creation.

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

=head1 SEE ALSO

L<LC::Process(8)>

=cut
