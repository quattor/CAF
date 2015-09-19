# ${license-info}
# ${developer-info}
# ${author-info}
# ${build-info}

package CAF::ObjectText;

use strict;
use warnings;

use parent qw(CAF::Object);
use LC::Exception qw (SUCCESS throw_error);

use overload ('""' => '_stringify');

use Readonly;
Readonly::Scalar my $DEFAULT_USECACHE => 1;

=pod

=head1 NAME

CAF::ObjectText - Base class for handling text

=head1 SYNOPSIS

Define subclass via
    package SubClass;
    use parent qw(CAF::ObjectText);

    sub _get_text
    {
        my ($self) = @_;
        return "actual text";
    }

And use it via
    my $sc = SubClass->new(log => $self);
    print "$sc"; # stringification

    $sc = SubClass->new(log => $self);
    # return CAF::FileWriter instance (text already added)
    my $fh = $sc->filewriter('/some/path');
    die "Problem rendering the text" if (!defined($fh));
    $fh->close();

=head1 DESCRIPTION

This class simplyfies text handling via stringification and producing
a C<CAF::FileWriter> instance.

=head2 Methods

=over

=item _initialize_textopts

Handle some common options in the subclass C<_initialize> method.

=over

=item C<log>

A C<CAF::Reporter> object to log to.

=item C<eol>

If C<eol> is true, the produced text will be verified that it ends with
an end-of-line, and if missing, a newline character will be added.
By default, C<eol> is true.

C<eol> set to false will not strip trailing newlines (use C<chomp>
or something similar for that).

=item C<usecache>

If C<usecache> is false, the text is always re-produced.
Default is to cache the produced text (C<usecache> is true).

=back

=cut

sub _initialize_textopts
{
    my ($self, %opts) = @_;

    %opts = () if !%opts;

    $self->{log} = $opts{log} if $opts{log};

    if (exists($opts{eol})) {
        $self->{eol} = $opts{eol};
        $self->verbose("Set eol to $self->{eol}");
    } else {
        # Default to true
        $self->{eol} = 1;
    };

    if(exists($opts{usecache})) {
        $self->{usecache} = $opts{usecache};
    } else {
        $self->{usecache} = $DEFAULT_USECACHE;
    }
    $self->verbose("No caching") if (! $self->{usecache});

}

=pod

=item fail

Handle failures. Stores the error message in the C<fail> attribute,
logs it with C<verbose> and returns undef.
All failures should use C<return $self->fail("message");>.
No error logging should occur in the subclass.

=cut

sub fail
{
    my ($self, @messages) = @_;
    $self->{fail} = join('', @messages);
    $self->verbose("FAIL: ", $self->{fail});
    return;
}

=pod

=item C<_get_text_test>

Run additional tests before the actual text is produced via C<get_text>.
Returns undef in case of failure, SUCCESS otherwise.

The method is called in C<get_text> before the caching is checked.

Default implementation does not test anything, always returns SUCCESS.
This method should be redefined in the subclass.

=cut

sub _get_text_test
{
    return SUCCESS;
}

=pod

=item C<_get_text>

Produce the actual text in C<get_text>
(or call another method that does so).

Returns 2 element tuple with first element the resulting text
(or undef in case of failure). The second element is an error message
prefix (ideally, real error message is set via the C<fail> attribute).

This method needs to be defined in the subclass.

=cut

sub _get_text
{
    my ($self) = @_;
    my $msg = "no _get_text implemented for ".ref($self);
    throw_error($msg);
    $self->fail($msg);
    return (undef, $msg);
}


=pod

=item C<get_text>

C<get_text> produces and returns the text.

In case of an error, C<get_text> returns C<undef>
(no error is logged).
This is the main difference from the auto-stringification that
returns an empty string in case of a rendering error.

By default, the result is cached. To force re-producing the text,
clear the current cache by passing C<1> as first argument
(or disable caching completely with the option C<usecache>
set to false during the initialisation).

=cut

sub get_text
{
    my ($self, $clearcache) = @_;

    return if (!$self->_get_text_test());

    if ($clearcache) {
        $self->verbose("get_text clearing cache");
        delete $self->{_cache};
    };

    if (exists($self->{_cache})) {
        $self->debug(1, "Returning the cached value");
        return $self->{_cache}
    };

    my ($res, $errmsg) = $self->_get_text();

    if (defined($res)) {
        if($self->{eol} && $res !~ m/\n$/) {
            $self->verbose("eol set, and rendered text was missing final newline. adding newline.");
            $res .= "\n";
        }
        if($self->{usecache}) {
            $self->{_cache} = $res;
        };
        return $res;
    } else {
        $errmsg = "No valid text produced from ".ref($self) if (! $errmsg);
        $errmsg .= ": $self->{fail}" if ($self->{fail});
        return $self->fail($errmsg);
    }
}


# Handle possible undef from get_text to avoid 'Use of uninitialized value' warnings
sub _stringify
{
    my ($self) = @_;
    # Always default cache behaviour
    my $text = $self->get_text();
    if(defined($text)) {
        return $text;
    } else {
        return "";
    }
}

=pod

=item C<filewriter>

Create and return an open C<CAF::FileWriter> instance with
first argument as the filename. If the C<get_text> method fails
(i.e. returns undef), C<undef> is returned.

The text is added to the filehandle.
It's up to the consumer to cancel
and/or close the instance.

All C<CAF::FileWriter> initialisation options are supported
and passed on. (If no C<log> option is provided,
 the one from the current instance is passed).

Two new options C<header> and C<footer> are supported
 to resp. prepend and append to the text.

If C<eol> was set during initialisation, the header and footer
will also be checked for EOL.
(EOL is still added to the C<get_text> if
C<eol> is set during initialisation, even if there is a footer
defined.)

=cut

sub filewriter
{
    my ($self, $file, %opts) = @_;

    # use get_text, not stringification to handle render failure
    my $text = $self->get_text();
    return if (!defined($text));

    my $header = delete $opts{header};
    my $footer = delete $opts{footer};

    $opts{log} = $self if(!exists($opts{log}));

    my $cfh = CAF::FileWriter->new($file, %opts);

    if (defined($header)) {
        print $cfh $header;

        if($self->{eol} && $header !~ m/\n$/) {
            $self->verbose("eol set, and header was missing final newline. adding newline.");
            print $cfh "\n";
        };
    };

    print $cfh $text;

    if (defined($footer)) {
        print $cfh $footer;

        if($self->{eol} && $footer !~ m/\n$/) {
            $self->verbose("eol set, and footer was missing final newline. adding newline.");
            print $cfh "\n";
        };
    };

    return $cfh
}

=pod

=back

=cut

1;
