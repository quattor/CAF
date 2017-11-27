#${PMpre} CAF::Exception${PMpost}

use CAF::Object qw(SUCCESS);

=pod

=head1 NAME

CAF::Exception - provides basic methods for failure and exception handling

=head2 Private methods

=over

=item _get_noaction

Return NoAction setting:

=over

=item Return 0 is C<keeps_state> is true

Any other value of C<keeps_state> is ignored. (In particular,
you cannot use C<keeps_state> to enable NoAction).

=item Return value of C<noAction> method (when defined)

=item C<CAF::Object::NoAction> otherwise

=back

Supports an optional C<msg> that is prefixed to reporter.


=cut

# TODO: move (again) somewhere else
#       this has nothing to do with exceptions, but cannot be in CAF::Object
sub _get_noaction
{
    my ($self, $keeps_state, $msg) = @_;

    $msg = '' if (! defined($msg));

    my $noaction;

    if ($keeps_state) {
        $self->debug(1, $msg, "keeps_state set, noaction is false");
        $noaction = 0;
    } else {
        if ($self->can('noAction')) {
            $noaction = $self->noAction();
        }

        $noaction = $CAF::Object::NoAction if ! defined($noaction);

        $self->debug(1, $msg, "noaction is ", ($noaction ? 'true' : 'false'));
    }

    return $noaction ? 1 : 0;
}

=item _reset_exception_fail

Reset previous fail attribute and/or exception.

C<msg> is a suffix when reporting the old C<fail> attribute
and/or exception error (with debug level 1).

C<EC> is a C<LC::Exception::Context> instance that is checked for an
existing error, which is set to ignore if it exists.

Always returns SUCCESS.

=cut

sub _reset_exception_fail
{
    my ($self, $msg, $EC) = @_;

    $msg = defined($msg) ? " ($msg)" : "";

    # Reset the fail attribute
    if ($self->{fail}) {
        $self->debug(1, "Ignoring/resetting previous existing fail$msg: ",
                     $self->{fail});
        $self->{fail} = undef;
    }

    # Ignore/reset any existing errors
    if ($EC->error()) {
        # LC::Exception supports formatted stringification
        my $errmsg = ''.$EC->error();
        $self->debug(1, "Ignoring/resetting previous existing error$msg: $errmsg");
        $EC->ignore_error();
    };

    return SUCCESS;
}


=item _function_catch

Execute function reference C<funcref> with arrayref C<$args> and hashref C<$opts>.

Method resets any existing fail attribute and error from C<LC::Exception::Context> instance C<EC>.

When an exception thrown is thrown, it is catched and reset. No error is reported
and undef is returned in this case and the fail attribute is set with the exception
error text.

=cut

sub _function_catch
{
    my ($self, $funcref, $args, $opts, $EC) = @_;

    $self->_reset_exception_fail('_function_catch', $EC);

    my $res = $funcref->(@$args, %$opts);

    if ($EC->error()) {
        # LC::Exception supports formatted stringification
        my $errmsg = ''.$EC->error();
        $EC->ignore_error();
        return $self->fail($errmsg);
    }

    return $res;
}

=item _safe_eval

Run function reference C<funcref> with arrayref C<argsref> and hashref C<optsref>.

Return and set fail attribute with C<failmsg> (C<$@> is added when set) on die
or in case of an error (C<undef> returned by C<funcref>).
In case of success, report C<msg> (stringified result is added unless C<sensitive> attribute is set)
at verbose level.

Note that C<_safe_eval> doesn't work with functions
that don't return a defined value when they succeed.

Resets previous fail attribute and or exceptions
(via the C<LC::Exception::Context> instance C<EC>).

=cut

sub _safe_eval
{
    my ($self, $funcref, $argsref, $optsref, $failmsg, $msg, $EC) = @_;

    $self->_reset_exception_fail('_safe_eval', $EC);

    my (@args, %opts);
    @args = @$argsref if $argsref;
    %opts = %$optsref if $optsref;

    local $@;
    my @res;
    my $res;
    # TODO: is there a cleaner way to avoid the copy/paste of the right hand side?
    if (wantarray) {
        @res = eval { $funcref->(@args, %opts);};
        # set $res, even in wantarray; it's used below
        $res = "@res";
    } else {
        $res = eval { $funcref->(@args, %opts);};
    }

    # $res is undef if there is a syntax or runtime error or if the evaluated
    # function returns undef (interpreted as a function error).
    if ( defined($res) ) {
        $self->verbose("$msg: ", ($self->{sensitive} ? "<sensitive>" : "$res"));
    } else {
        my $err_msg = '';
        if ($@) {
            chomp($@);
            $err_msg = ": $@";
        }
        return $self->fail("$failmsg$err_msg");
    }

    return wantarray ? @res : $res;
}


=pod

=back

=cut

1;
