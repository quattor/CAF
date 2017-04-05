#${PMpre} CAF::FileWriter${PMpost}

use LC::Exception qw(throw_error);
use LC::File;
use Text::Diff qw(diff);
use File::AtomicWrite 1.18;
use Errno qw(ENOENT);
use IO::String;
use CAF::Process;
use CAF::Object;
use overload '""' => "stringify";

our @ISA = qw (IO::String);

our $_EC = LC::Exception::Context->new()->will_store_errors();

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

This is a wrapper class for C<IO::String> with customised close based on
C<File::AtomicWrite>.

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

=item C<keeps_state>

A boolean specifying whether a file change respects the current system
state or not. A file with C<keeps_state> will be created/modified,
regardless of any value for C<NoAction>.
This is useful when creating temporary files that are required for a NoAction run.

By default, file changes modify the state and thus C<keeps_state> is
false.

=item C<sensitive>

A boolean specifying whether a file contains sensitive information
(like passwords). When the content of the file is modified, the changes
(either the diff or the whole content in case of a new file) themself
are not reported and not added to the event history.

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
    *$self->{options}->{sensitive} = $opts{sensitive} if exists ($opts{sensitive});

    *$self->{save} = 1;
    bless ($self, $class);

    my $noaction = defined($CAF::Object::NoAction) ? $CAF::Object::NoAction : 0;
    if ($opts{keeps_state}) {
        $self->verbose("keeps_state set for filename $path: forcing NoAction $noaction to 0.");
        # Only set 0, do not set the value via keeps_state logic
        # (in particular, you cannot use keeps_state to set noaction to 1)
        $noaction = 0;
    }
    # This garantees that *$self->{options} is a non-empty hashref
    *$self->{options}->{noaction} = $noaction;

    # Tracking on new() when CAF::History is setup to track INSTANCES
    $self->event(init => 1);

    return $self;
}

=item open

Synonym for C<new()>

=cut

# Alias open to new.
no warnings 'redefine';
*open = \&new;
use warnings;

=item close

Closes the file.

If the file has been saved (e.g. previous C<close> or C<cancel>)
nothing happens and undef is returned.

If the file has not been saved,
it checks its contents and perhaps re-writes it, in a
secure way (not following symlinks, etc). The (re)write only occurs
if there was a change in content and this change (or not) is
always determined and returned, even if C<NoAction> is true
(but in that case nothing is (re)written).

Under a verbose level, it will show in the standard output a diff of
the old and the newly-generated contents for this file before actually
saving to disk.

=cut

# If the C<original_content> atttribute exists, it is used to determine
# whether or not there was a change and a consequent write; unless
# the C<original_from_source> attribute is true
# (e.g. in case of C<CAF::FileEditor> with C<source> option).
# If C<original_from_source> is true, changes to the C<orginal_content> will
# be reported; but the actual file change (and possible (re)write)
# is based on a (re)read of the file content.

sub close
{
    my $self = shift;

    my $filename = *$self->{filename};
    my $options = *$self->{options};

    my $modified = 0;
    my $changed;

    my %event = (
        noaction => $options->{noaction},
        save => *$self->{save},
        backup => $options->{backup},
    );

    if (*$self->{save}) {
        *$self->{save} = 0;
        my $content_ref = $self->string_ref();

        my $report_diff = sub {
            my ($diff, $msg) = @_;
            if(*$self->{options}->{sensitive}) {
                $self->verbose("Changes $msg $filename are not reported due to sensitive content");
            } else {
                $self->verbose("Changes $msg $filename:");
                if ($self->is_verbose()) {
                    $self->report($diff);
                } elsif ($self->is_verbose(verbose_logfile => 1)) {
                    $self->log($diff);
                }
            }
        };

        if (*$self->{original_from_source}) {
            # Report changes compared to source
            my $src_original_content = *$self->{original_content};
            if (defined($src_original_content)) {
                my $src_diff = diff(\$src_original_content, $content_ref, { STYLE => "Unified" });
                if ($src_diff) {
                    $report_diff->($src_diff, 'compared to source for');
                } else {
                    $self->verbose("No changes compared to source for $filename");
                }
            } else {
                $self->verbose("No original source content for $filename");
            }
        }

        my $original_content;
        if (defined(*$self->{original_content}) && !*$self->{original_from_source}) {
            # Use the existing original_content attribute to compare instead of (re)reading the file
            #   This is the case for FileEditor without source (and avoids a reread of same file)
            $self->debug(2, "Using existing original content for $filename");
            $original_content = *$self->{original_content};
        } else {
            # Get the content to compare from the file
            #   This is a (first) read in case of FileWriter
            #   This is a (first) read in case of FileEditor with source
            # missing_ok=1 mimics original LC::Check::file behaviour
            $original_content = $self->_read_contents($filename, event => \%event, missing_ok => 1);
        }

        # Always try to determine the diff
        my $diff;
        if (defined($original_content)) {
            $diff = diff(\$original_content, $content_ref, { STYLE => "Unified" });
            $changed = $diff ? 1 : 0;
        } else {
            $self->verbose("No original content for $filename; new content is the diff");

            $diff = $$content_ref;
            $changed = 1;
        }

        # Update event metadata with diff
        $event{changed} = $changed;
        if ($changed && ! *$self->{options}->{sensitive}) {
            $event{diff} = $diff
        }

        my $msg = 'was';

        if ($changed) {
            $report_diff->($diff, 'to');

            if ($self->noAction()) {
                $msg = 'would have been';
                $self->debug(1, "File $filename with NoAction=1");
            } else {
                my $opts = {
                    file => $filename,
                    input => $content_ref,
                    MKPATH => 1, # create missing parent directory
                };
                # group is handled separately
                foreach my $name (qw(mode mtime backup owner)) {
                    $opts->{$name} = $options->{$name} if exists($options->{$name});
                };
                # No need to check if owner exists. :groupname is supported
                $opts->{owner} .= ":$options->{group}" if exists($options->{group});

                eval {
                    File::AtomicWrite->write_file($opts);
                    $modified = 1;
                };
                if ($@) {
                    $self->warn("AtomicWrite gave error: $@");
                    # Make an oldstyle exception
                    throw_error("close AtomicWrite failed filename $filename: $@");
                }

                # Restore the SELinux context in case of modifications.
                $self->change_hook();
            }
        } else {
            $msg = 'was not';
        }

        $self->verbose("File $filename $msg modified");
    } else {
        $self->verbose("Not saving file $filename");
    }

    # Always keep the modified state, even with save==0
    $event{modified} = $modified;
    $self->event(%event);

    $self->SUPER::close();
    return $changed;
}

=item cancel

Marks the printed contents as invalid. The existing file will not be
altered.

Option C<msg> to add custom message to verbose reporting.

=cut

sub cancel
{
    my ($self, %opts) = @_;

    my $msg = defined($opts{msg}) ? $opts{msg} : 'cancelled';

    $self->verbose("Will not save file ", *$self->{filename}, " ($msg)");

    *$self->{save} = 0;
}

=item noAction

Returns the NoAction flag value (boolean)

=cut

sub noAction
{
    my $self = shift;
    return *$self->{options}->{noaction};
}

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

=item error, warn, info, verbose, debug, report, log, OK

Convenience methods to access the log/reporter instance that might
be passed during initialisation and set to C<*$self->{LOG}>.

=cut


no strict 'refs';
foreach my $i (qw(error warn info verbose debug report log OK)) {
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

Supports boolean option C<verbose_logfile> to check if
reporting to logfile is verbose.

=cut

sub is_verbose
{
    my ($self, %opts) = @_;

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

        if(UNIVERSAL::can($log, 'can') && $log->can('is_verbose')) {
            $res = $log->is_verbose(%opts);
        } else {
            # Fallback to CAF::Reporter
            # must use 'require' for evaluation at runtime
            # ('use' is evaluated at compile time and might trigger a cyclic dependency eg in TextRender).
            require CAF::Reporter;
            my $attr = $opts{verbose_logfile} ? 'VERBOSE_LOGFILE' : 'VERBOSE';
            $res = $CAF::Reporter::_REP_SETUP->{$attr};
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

=item _read_contents

Read the contents from file C<filename> using C<LC::File::file_contents>
and return it.

Optional named arguments

=over

=item event

A hashref that will be updated in place if an error occured. The C<error>
attribute is set to the exception text.

=item missing_ok

When true and C<LC::File::file_contents> fails with C<ENOENT>
(i.e. when C<filename> is missing),
the exception is ignored and no warning is reported.

=back

By default, a warning is reported in case of an error and the exception is (re)thrown.

=cut

sub _read_contents
{
    my ($self, $filename, %opts) = @_;

    $self->debug(2, "Reading initial contents from $filename");
    my $contents = LC::File::file_contents($filename);
    if ($_EC->error) {
        if ($opts{missing_ok} and $_EC->error()->reason() == ENOENT) {
            # the filename does not exist (yet), and this is ok
            $self->verbose("No contents from missing $filename");
            $_EC->ignore_error();
	    } else {
            my $errtxt = $_EC->error->text();

            $opts{event}->{error} = $errtxt if defined $opts{event};
            $self->warn("Reading contents from $filename gave error: $errtxt");

            # Keep legacy exception behaviour
            $_EC->rethrow_error();
            return();
        }
    };

    return $contents;
}


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
