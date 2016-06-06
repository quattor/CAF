${PMpre} CAF::Path${PMpost}

use CAF::Object qw(SUCCESS CHANGED);
use LC::Check;
use LC::Exception qw (throw_error);

use Readonly;

use File::Path qw(rmtree);
use File::Copy qw(move);
use File::Temp qw(tempdir);
use File::Basename qw(dirname);

use Scalar::Util qw(dualvar);

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
};

Readonly::Array my @LC_CHECK_SILENT_FUNCTIONS => qw(directory status file link symlink hardlink absence);

our $EC = LC::Exception::Context->new->will_store_all;

=pod

=head1 NAME

CAF::Path - check that things are really the way we expect them to be

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

=item return values

=over

=item undef: failure occured

=item SUCCESS: nothing changed (boolean true)

=item CHANGED: something changed (boolean true).

=back

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

=item _reset_exception_fail

Reset previous exceptions and/or fail attribute.

=cut

# TODO: move to CAF::Object ?

sub _reset_exception_fail
{
    my ($self) = shift;

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

    return SUCCESS;
}


=item _function_catch

Execute function reference C<funcref> with arrayref C<$args> and hashref C<$opts>.

Method resets/ignores any existing errors and fail attribute, and catches any exception thrown.
No error is reported, it returns undef in this case and the fail attribute is set.

=cut

sub _function_catch
{
    my ($self, $funcref, $args, $opts) = @_;

    $self->_reset_exception_fail();

    my $res = $funcref->(@$args, %$opts);

    if ($EC->error()) {
        # LC::Exception supports formatted stringification
        my $errmsg = ''.$EC->error();
        $EC->ignore_error();
        return $self->fail($errmsg);
    }

    return $res;
}

# TODO: move to CAF::Object ?

=item _safe_eval

Run function reference C<funcref> with arrayref C<argsref> and hashref C<optsref>.

Return and set fail attribute with C<failmsg> on die, verbose C<msg> on success
(resp. $@ and stringified result are appended).

Resets previous exceptions and/or fail attribute

=cut

sub _safe_eval
{
    my ($self, $funcref, $argsref, $optsref, $failmsg, $msg) = @_;

    $self->_reset_exception_fail();

    my ($res, @args, %opts);
    @args = @$argsref if $argsref;
    %opts = %$optsref if $optsref;

    local $@;
    eval {
        $res = $funcref->(@args, %opts);
    };

    if($@) {
        chomp($@);
        return $self->fail("$failmsg: $@");
    } else {
        my $res_txt = defined($res) ? "$res" : '<undef>';
        chomp($res);
        $self->verbose("$msg: $res");
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

    # make sure LC::Check::$function is silent unless in noaction mode
    # (or when explicitly set via silent option)
    if (! defined($opts->{silent}) &&
        grep {$_ eq $function} @LC_CHECK_SILENT_FUNCTIONS
        ) {
        $opts->{silent} = $noaction ? 0 : 1
    };


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

Returns CHANGED is something was cleaned-up, SUCCESS if nothing was done
and undef on failure (and sets the fail attribute).

The <backup> is a suffix for C<dest>.

If backup is undefined, use C<backup> attribute.
(Pass an empty string to disable backup with C<backup> attribute defined)
Any previous backup is C<cleanup>ed (without backup).
(Aside from the C<backup> attribute, this is the same as C<LC::Check::_unlink>
(and thus also C<CAF::File*>)).

=cut

# TODO: is the $self->{backup} a good idea?

sub cleanup
{
    my ($self, $dest, $backup, %opts) = @_;

    $self->_reset_exception_fail();

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
            return $self->fail("cleanup of previous backup $old failed");
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
    } else {
        my $res = $self->_safe_eval(
            $CLEANUP_DISPATCH{$method}, \@args, undef,
            "Cleanup $method failed to remove $dest",
            "Cleanup $method removed $dest",
            );
        # move and unlink return 0 on failure, set $!
        # rmtree dies on failure
        if ($method eq 'rmtree') {
            return if defined($self->{fail});
        } else {
            return $self->fail("Cleanup $method failed to remove $dest: $!") if ! $res;
        };
    };

    return CHANGED;
}


=item directory

Make sure a directory exists with proper options.

If the directory does not exists (or the C<temp> option is set),
it is created (including the parent directories as needed),
and uses C<LC::Check::directory> via C<LC_Check>.

Returns CHANGED if a change was made, SUCCESS if no changes were made
and undef in case of failure (and the C<fail> attribute is set).

The return value in absence of failure is a dualvar with integer value
SUCCESS/CHANGED, and the directory as string value
(in particular relevant for temporary directories).

Additional options

=over

=item owner/group/mode/mtime : options for C<CAF::Path::status>

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

# Differences with LC::Check::directory
#    only accepts one directory
#    returns directory name or undef (LC::Check::directory returns number of created directories)
#    tempdir support
#    set the status of existing directory
#    set the owner/group/mtime of new directory
#
# perl5.8.8 has no Temp::File->new() way of making a tempdir
# tempdir + CLEANUP is supported in 5.8.8x

sub directory
{
    my ($self, $directory, %opts) = @_;

    # assume we will create a new directory
    my $newdir = 1;

    $self->_reset_exception_fail();

    if (delete $opts{temp}) {
        # pad to at least X by adding 4
        $directory .= 'X' x 4 if $directory !~ m/X{4}$/;

        if($self->_get_noaction($opts{$KEEPS_STATE}, "directory: (tempdir) ")) {
            $self->verbose("NoAction set, not going to create a temporary directory $directory with tempdir");
        } else {
            my $base = dirname($directory);
            if (! $self->directory_exists($base)) {
                if (! $self->directory($base, %opts)) {
                    return $self->fail("Failed to create basedir for temporary directory $directory");
                };
            }

            $directory = $self->_safe_eval(
                \&tempdir, [$directory], {CLEANUP => 1},
                "Failed to create temporary directory $directory",
                "Created temporary directory with tempdir",
                );
            return if defined($self->{fail});
        }
    } elsif ($self->directory_exists($directory)) {
        $newdir = 0;
    } else {
        # Directory does not exist
        # LC_Check directory returns false only if there was a problem
        # Only mode option is used
        my $dopts = {%opts}; # a copy
        foreach my $invalid_opt (qw(user group mtime)) {
            delete $dopts->{$invalid_opt};
        }
        return if ! $self->LC_Check('directory', [$directory], $dopts);
    };

    # Always run status, but track newly created directories
    my $status = $self->status($directory, %opts);
    return if ! defined($status);

    # If we got here, no failures occured.
    # A new directory always implies something changed
    my $changed = ($newdir || $status == CHANGED) ? CHANGED : SUCCESS;
    return dualvar( $changed, $directory);
}


=item status

Set the path stat options: C<owner>, C<group>, C<mode> and/or C<mtime>.

This is a wrapper around C<LC::Check::status>
and executed with C<LC_Check>.

Returns CHANGED if a change was made, SUCCESS if no changes were made
and undef in case of failure (and the C<fail> attribute is set).

=cut

# Satus on missing files returns undef (and file is not created).
# Status on a missing file returns CHANGED with NoAction.


sub status
{
    my ($self, $path, %opts) = @_;
    my $status = $self->LC_Check("status", [$path], \%opts);
    if(defined($self->{fail})) {
        return;
    } else {
        return $status ? CHANGED : SUCCESS;
    }
}

=pod

=back

=cut

1;
