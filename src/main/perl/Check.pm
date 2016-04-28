${PMpre} CAF::Check${PMpost}

use CAF::Object;
use LC::Check;
use LC::Exception qw (SUCCESS throw_error);
use Readonly;

use File::Path qw(rmtree);
use File::Copy qw(move);
use File::Temp qw(tempdir);
use File::Basename qw(dirname);

Readonly my $KEEPS_STATE => 'keeps_state';

Readonly::Hash my %CLEANUP_DISPATCH => {
    move => \&move,
    rmtree => \&rmtree,
    unlink => sub { return unlink(shift); },
};

# Use dispatch table instead of non-strict function by variable call
Readonly::Hash my %LC_CHECK_DISPATCH => {
    directory => \&LC::Check::directory,
    status => \&LC::Check::status,
    reset_exception => sub {return 1;}, # do nothing
};

our $EC = LC::Exception::Context->new->will_store_all;

=pod

=head1 NAME

CAF::Check - check that things are really the way we expect them to be

=head1 DESCRIPTION

Simplify common file and directory related operations e.g.

=over

=item directory creation

=item cleanup

=item (mockable) file/directory tests

=back

The class is based on L<LC::Check> with following major difference

=over

=item C<CAF::Object::NoAction> support builtin (and C<keeps_state> option to override it).

=item support C<CAF::Reporter> (incl. C<CAF::History>)

=item raised exceptions are catched, methods return SUCCESS on succes,
undef on failure and store the error message in the C<fail> attribute.

=item available as class-methods

=back

=head2 Methods

=over

=cut

# TODO: do we need some magic to be able to use as regular exported functions
# TODO: handle LC::Check _message, should use Reporter instead of print

=item _get_noaction

Return NoAction setting:

=over

=item Return 0 is C<keeps_state> is true

Any other value of C<keeps_state> is ignored. (In particular,
you cannot use C<keeps_state> to enable NoAction).

=item Return value of C<CAF::Object::NoAction> otherwise.

=back

Supports an optional C<msg> that is prefixed to reporter.

=cut


sub _get_noaction
{
    my ($self, $keeps_state, $msg) = @_;

    $msg = '' if (! defined($msg));

    my $noaction;

    if ($keeps_state) {
        $self->debug(1, $msg, "keeps_state set, noaction is false");
        $noaction = 0;
    } else {
        $noaction = $CAF::Object::NoAction ? 1 : 0;
        $self->debug(1, $msg, "noaction is ", ($noaction ? 'true' : 'false'));
    }

    return $noaction;
}

=item _function_catch

Execute function reference C<funcref> with arrayref C<$args> and hashref C<$opts>.

Method resets/ignores any existing errors and fail attribute, and catches any exception thrown.
No error is reported, it returns undef in this case and the fail attribute is set.

=cut

sub _function_catch
{
    my ($self, $funcref, $args, $opts) = @_;

    # Reset the fail attribute
    if ($self->{fail}) {
        $self->debug(1, "Ignoring/resetting previous existing fail: ",
                       $self->{fail});
        $self->{fail} = undef;
    }

    # Ignore/reset any existing errors
    if ($EC->error()) {
        # LC::Exception supports formatted stringification
        my $errmsg = ''.$EC->error();
        $self->debug(1, "Ignoring/resetting previous existing error: $errmsg");
        $EC->ignore_error();
    };

    my $res = $funcref->(@$args, %$opts);

    if ($EC->error()) {
        # LC::Exception supports formatted stringification
        my $errmsg = ''.$EC->error();
        $EC->ignore_error();
        return $self->fail($errmsg);
    }

    return $res;
}

=item LC_Check

Execute function C<<LC::Check::<function>>> with arrayref C<$args> and hashref C<$opts>.

C<CAF::Object::NoAction> is added to the options, unless C<keeps_state> is set.

The function is executed with C<_function_catch>.

=cut

sub LC_Check
{
    my ($self, $function, $args, $opts) = @_;

    my $noaction = $self->_get_noaction($opts->{$KEEPS_STATE});
    delete $opts->{$KEEPS_STATE};

    # Override noaction passed via opts
    $opts->{noaction} = $noaction;

    my $funcref = $LC_CHECK_DISPATCH{$function};
    if (defined($funcref)) {
        return $self->_function_catch($funcref, $args, $opts);
    } else {
        return $self->fail("Unsupported LC::Check function $function");
    };
}

=item directory_exists

Test if C<directory> exists and is a directory.

This is basically the perl builtin C<-d>,
wrapped in a method to allow unittesting.

A broken symlink is not a directory. (As C<-d> follows a symlink,
a broken symlink either exists with C<-l> or not.)

=cut

sub directory_exists
{
    my ($self, $directory) = @_;
    return $directory && -d $directory;
}

=item file_exists

Test if C<filename> exists ans is a directory.

This is basically the perl builtin C<-f>,
wrapped in a method to allow unittesting.

A broken symlink is not a file. (As C<-f> follows a symlink,
a broken symlink either exists with C<-l> or not.)

=cut

sub file_exists
{
    my ($self, $filename) = @_;
    return $filename && -f $filename;
}

=item any_exists

Test if C<path> exists.

This is basically the perl builtin C<-e || -l>,
wrapped in a method to allow unittesting.

A broken symlink exists. As C<-e> follows a symlink,
a broken symlink either exists with C<-l> or not.

=cut

# LC::Check::_unlink uses lstat and -e _ (is that a single FS query?)

sub any_exists
{
    my ($self, $path) = @_;
    return $path && (-e $path || -l $path);
}

=item cleanup

cleanup removes C<dest> with backup support.

(Works like C<LC::Check::_unlink>, but has directory support
and no error throwing).

Returns SUCCESS on success; on failure it returns undef and reports error.

The <backup> is a suffix for C<dest>.

If backup is undefined, use C<backup> attribute.
(Pass an empty string to disable backup with C<backup> attribute defined)
Any previous backup is C<cleanup>ed (without backup).
(Aside from the C<backup> attribute, this is the same as C<LC::Check::_unlink>
(and thus also C<CAF::File*>)).

=cut

# TODO: option to not report error? (but if no error reporting is required on failure,
#       why bother to cleanup in the first place?)
# TODO: is the $self->{backup} a good idea?

sub cleanup
{
    my ($self, $dest, $backup, %opts) = @_;

    return SUCCESS if (! $self->any_exists($dest));

    $backup = $self->{backup} if (! defined($backup));

    # old is the backup location or undef if no backup is defined
    # (empty string as backup is not allowed, but 0 is)
    # 'if ($old)' can safely be used to test if a backup is needed
    my $old;
    $old = $dest.$backup if (defined($backup) and $backup ne '');

    # cleanup previous backup, no backup of previous backup!
    my $method;
    my @args = ($dest);
    if ($old) {
        if (! $self->cleanup($old, '', %opts)) {
            $self->error("cleanup of previous backup $old failed");
            return;
        };

        # simply rename/move dest to backup
        # works for files and directories
        $method = 'move';
        push(@args, $old);
    } else {
        if($self->directory_exists($dest)) {
            $method = 'rmtree';
        } else {
            $method = 'unlink';
        }
    }

    if($self->_get_noaction($opts{$KEEPS_STATE}, "cleanup: ")) {
        $self->verbose("NoAction set, not going to $method with args ", join(',', @args));
        return SUCCESS;
    } else {
        if($CLEANUP_DISPATCH{$method}->(@args)) {
            $self->verbose("cleanup $method removed $dest");
            return SUCCESS;
        } else {
            $self->error("cleanup $method failed to remove $dest: $!");
            return;
        }
    };
}


=item directory

Make sure a directory exists. If not, it is created.

Makes parent directories as needed,
is a wrapper around C<LC::Check::directory>
and executed with C<LC_Check>.

Returns the directory name on SUCCESS, undef otherwise.

Additional options

=over

=item temp

A boolean if true will create a a temporary directory using
L<File::Temp::tempdir>.

The directory name is the template to use (any trailing
C<X> characters will be replaced with random characters by C<tempdir>;
and the directory name will be padded up to at least 4 C<X>).

The C<CLEANUP> option is also set (an removal
attempt (incl. any files and/or subdirectries)
will be made at the end of the program).

=back

=cut

# perl5.8.8 has no Temp::File->new() way of making a tempdir
# tempdir + CLEANUP is supported in 5.8.8x

sub directory
{
    my ($self, $directory, %opts) = @_;

    my $is_temp = delete $opts{temp};

    if ($is_temp) {
        # pad to at least X by adding 4
        $directory .= 'X' x 4 if $directory !~ m/X{4}$/;

        if($self->_get_noaction($opts{$KEEPS_STATE}, "directory: (tempdir) ")) {
            $self->verbose("NoAction set, not going to create a temporary directory $directory with tempdir");
        } else {
            # reset any exceptions
            $self->_function_catch($LC_CHECK_DISPATCH{reset_exception});

            my $base = dirname($directory);
            if (! $self->directory_exists($base)) {
                if (! $self->directory($base, %opts)) {
                    return $self->fail("Failed to create basedir for temporary directory $directory");
                };
            }

            local $@;
            eval {
                $directory = tempdir($directory, CLEANUP => 1);
            };

            if($@) {
                chomp($@);
                return $self->fail("Failed to create temporary directory $directory: $@");
            } else {
                $self->verbose("Created temporary directory $directory with tempdir");
            }
        }
    }

    return defined($self->LC_Check("directory", [$directory], \%opts)) ? $directory : undef;
}

=item status

Set the path stat options: C<owner>, C<group>, C<mode> and/or C<mtime>.

This is a wrapper around C<LC::Check::status>
and executed with C<LC_Check>.

=cut

sub status
{
    my ($self, $path, %opts) = @_;
    return $self->LC_Check("status", [$path], \%opts);
}

=pod

=back

=cut

1;
