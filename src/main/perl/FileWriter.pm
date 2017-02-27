#${PMpre} CAF::FileWriter${PMpost}
use LC::Check;
use IO::String;
use CAF::Process;
use CAF::Object;
use overload '""' => "stringify";

our @ISA = qw (IO::String);


# This code makes sense only in Linux with SELinux enabled.  Other
# platforms might require other adjustments after files are written.
*change_hook = sub{};
if ($^O eq 'linux'){
    # temporarily remove PATH environment
    # allows for 'use CAF::FileWriter' under -T without warnings
    local $ENV{PATH};
    delete $ENV{PATH};
    if(CAF::Process->new(["/usr/sbin/selinuxenabled"])->run() && $? == 0) {
        no warnings 'redefine';
        *change_hook = sub {
            my $self = shift;
            my $cmd = CAF::Process->new (['/sbin/restorecon', *$self->{filename}],
                                         log => *$self->{LOG});
            $cmd->run();
        };
    };
}


=pod

=head1 NAME

CAF::FileWriter - Class for securely writing to files in CAF
applications.

=head1 SYNOPSIS

Normal use:

    use CAF::FileWriter;
    my $fh = CAF::FileWriter->open ("my/path");
    print $fh "My text";
    $fh->close();

Aborting changes:

    use CAF::FileWriter;
    my $fh = CAF::FileWriter->open ("my/path");
    print $fh, "My text";
    $fh->cancel();
    $fh->close();

=head1 DESCRIPTION

This class should be used whenever a file is to be opened for writing.

If the file already exists and the printed contents are the same as
the contents present on disk, the actual file won't be modified. This
way, timestamps will be kept.

It also provides a secure way of opening files, avoiding symlink
attacks.

In case of errors, changes can be cancelled, and nothing will happen
to disk.

Finally, the file names to be handled will be logged at the verbose
level.

=head2 Gory details

This is just a wrapper class for C<LC::Check::file>

=head2 Public methods

=over

=item new

Returns a new object. It accepts the file name as its first argument,
and the next hash as additional options:

=over

=item C<log>

The log object. If not supplied, no logging will be performed.

=item C<owner>

UID for the file.

=item C<group>

File's GID.

=item C<mode>

File's permissions.

=item C<mtime>

File's modification time.

=item C<backup>

Path for the backup file, if this one has to be re-written.

=item keeps_state

A boolean specifying whether a file change respects the current system
state or not. A file with C<keeps_state> will be created/modified,
regardless of any value for C<NoAction>.
This is useful when creating temporary files that are required for a NoAction run.

By default, file changes modify the state and thus C<keeps_state> is
false.

=back

=cut

sub new
{
    my ($class, $path, %opts) = @_;

    my $self = IO::String->new();

    *$self->{filename} = $path;
    *$self->{LOG} = $opts{log} if exists ($opts{log});
    *$self->{LOG}->verbose ("Opening file $path") if exists (*$self->{LOG});
    *$self->{options}->{mode} = $opts{mode} if exists ($opts{mode});
    *$self->{options}->{owner} = $opts{owner} if exists ($opts{owner});
    *$self->{options}->{group} = $opts{group} if exists ($opts{group});
    *$self->{options}->{mtime} = $opts{mtime} if exists ($opts{mtime});
    *$self->{options}->{backup} = $opts{backup} if exists ($opts{backup});
    *$self->{save} = 1;
    bless ($self, $class);

    my $noaction = defined($CAF::Object::NoAction) ? $CAF::Object::NoAction : 0;
    if ($opts{keeps_state}) {
        $self->verbose("keeps_state set for filename $path: forcing NoAction $noaction to 0.");
        # Only set 0, do not set the value via keeps_state logic
        # (in particular, you cannot use keeps_state to set noaction to 1)
        $noaction = 0;
    }
    *$self->{options}->{noaction} = $noaction;

    # Tracking on new() when CAF::History is setup to track INSTANCES
    $self->event(init => 1);

    return $self;
}

=pod

=item open

Synonym for C<new()>

=cut

# Alias open to new.
no warnings 'redefine';
*open = \&new;
use warnings;


=item close

Closes the file. If it has not been saved and it has not been
cancelled, it checks its contents and perhaps re-writes it, in a
secure way (not following symlinks, etc).

Under a verbose level, it will show in the standard output a diff of
the old and the newly-generated contents for this file before actually
saving to disk. This diff will B<not> be stored in any logs to prevent
any leakages of confidential information (f.i. when writing to
/etc/shadow).

=cut

sub close
{
    my $self = shift;
    my ($str, $ret, $cmd, $diff);

    # We have to do this because Text::Diff is not present in SL5. :(
    if ($self->is_verbose() && -e *$self->{filename} && *$self->{buf}) {
        $cmd = CAF::Process->new (["diff", "-u", *$self->{filename}, "-"],
                                  stdin => "$self", stdout => \$diff,
                                  keeps_state => 1);
        $cmd->execute();
        if ($diff) {
            $self->verbose ("Changes to ", *$self->{filename}, ":");
            $self->report ($diff);
        } else {
            $self->debug(1, "No changes to make to ", *$self->{filename});
        }
    }

    if (*$self->{save}) {
        *$self->{save} = 0;
        $str = *$self->{buf};
        *$self->{options}->{contents} = $$str;

        my %cf_opts = %{*$self->{options}};
        if(! exists($cf_opts{silent})) {
            # make sure LC::Check::file is silent unless in noaction mode
            # (or when explicitly set via silent option)
            $cf_opts{silent} = *$self->{options}->{noaction} ? 0 : 1
        }

        $ret = LC::Check::file (*$self->{filename}, %cf_opts);
        # Restore the SELinux context in case of modifications.
        if ($ret) {
            $self->change_hook();
        }
        $self->verbose("File ", *$self->{filename}, " was", ($ret ? '' : ' not')," modified");
    }

    $self->event(modified => $ret,
                 noaction => *$self->{options}->{noaction}, # TODO: useful to track?
                 backup => *$self->{options}->{backup},
                 );

    $self->SUPER::close();
    return $ret;
}

=item cancel

Marks the printed contents as invalid. The existing file will not be
altered.

=cut

sub cancel
{
    my $self = shift;

    $self->verbose("Not saving file ", *$self->{filename});

    *$self->{save} = 0;
}

=pod

=item noAction

Returns the NoAction flag value (boolean)

=cut

sub noAction
{
    my $self = shift;
    return *$self->{options}->{noaction};
}

=pod

=item stringify

Returns a string with the contents of the file, so far. It overloads
C<"">, so it's now possible to do "$fh" and get the contents of the
file so far.

=cut

sub stringify
{
     my $self = shift;
     my $str = $self->string_ref;
     return $$str;
}

# Compatibility with CAF::Object
# event is handled differently (as opposed to CAF::Object).

=item error, warn, info, verbose, debug, report, OK

Convenience methods to access the log/reporter instance that might
be passed during initialisation and set to C<*$self->{LOG}>.

=cut


no strict 'refs';
foreach my $i (qw(error warn info verbose debug report OK)) {
    *{$i} = sub {
        my ($self, @args) = @_;
        if (*$self->{LOG}) {
            return *$self->{LOG}->$i(@args);
        } else {
            return;
        }
    }
}
use strict 'refs';

=item is_verbose

Determine if the reporter level is verbose.
If it can't be determined from the reporter instance,
use the global C<CAF::Reporter> state.

=cut

sub is_verbose
{
    my $self = shift;

    my $res;
    if (*$self->{LOG}) {
        my $log = *$self->{LOG};

        if (defined($log->{LOGGER})) {
            # ComponentProxy as reporter
            $log = $log->{LOGGER};
        } elsif (defined($log->{log})) {
            # CAF::Object as reporter
            $log = $log->{log};
        };

        if($log->can('is_verbose')) {
            $res = $log->is_verbose();
        } else {
            # Fallback to CAF::Reporter
            # must use 'require' for evaluation at runtime
            # ('use' is evaluated at compile time and might trigger a cyclic dependency eg in TextRender).
            require CAF::Reporter;
            $res = $CAF::Reporter::_REP_SETUP->{VERBOSE};
        };
    }
    return $res;
};


=item event

Method to track an event via LOG C<CAF::History> instance (if any).

Following metadata is added

=over

=item filename

Adds the filename as metadata

=back

=cut

sub event
{
    my ($self, %metadata) = @_;

    $metadata{filename} = *$self->{filename};

    my $res;
    if (*$self->{LOG}) {
        $res = *$self->{LOG}->event($self, %metadata);
    }
    return $res;
}


=back

=head2 Private methods

=over

=item DESTROY

Class destructor. Closes the file, perhaps saving it to disk.

=back

=cut


sub DESTROY
{
    my $self = shift;
    $self->close();
    $self->SUPER::DESTROY();
}

1;



__END__

=pod

=head1 EXAMPLES

=head2 Opening /etc/sudoers

This a part of what I<ncm-sudo> should do, if it used this module:

    my $fh = CAF::FileWriter->open ("/etc/sudoers", mode => 0440,
                                    log => $self);
    print $fh "User_Alias\t$_\n" foreach @{$aliases->{USER_ALIASES()}};
    print $fh "Runas_Alias\t$_\n" foreach @{$aliases->{RUNAS_ALIASES()}};
    ...
    $fh->close();

Which is actually simpler and safer than current code.

=head2 Specifying owner and group

Owner and group are set at the time of creating the object:

    my $fh = CAF::FileWriter->open ("/some/file",
                                    owner => 100
                                    group => 200);
    print $fh "Hello, world!\n";
    # I don't like what I did, just drop the changes:
    $fh->cancel();
    $fh->close();

=head2 Changing the default filehandle

If you don't want C<STDOUT> as your default filehandle, you can just
C<select> a C<CAF::FileWriter> object:

    my $fh = CAF::FileWriter->open ("/some/file",
                                    owner => 100,
                                    group => 200);
    select ($fh);
    print "Hello, world!\n";
    $fh->close();
    select (STDOUT);

=head2 Using here-documents

You can use them, as always:

    my $fh = CAF::FileWriter->open ("/some/file");
    print $fh <<EOF
    Hello, World!
    EOF
    $fh->close();

=head2 Closing when destroying

If you forget to explictly close the C<CAF::FileWriter> object, it
will be closed automatically when it is destroyed:

    my $fh = CAF::FileWriter->open ("/some/file");
    print $fh "Hello, world!\n";
    undef $fh;

=head1 SEE ALSO

This package inherits from L<IO::String(3pm)>. Check its man page to
do powerful things with the already printed contents.

=head1 TODO

This has became too heavy: in some circumstances, manipulating a file
involves opening it three times, reading it twice and executing two
commands. We probably need to drop LC::* and do things in our own way.

=cut
