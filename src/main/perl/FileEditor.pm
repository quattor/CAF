# ${license-info}
# ${developer-info
# ${author-info}
# ${build-info}
#
package CAF::FileEditor;

use strict;
use warnings;
use CAF::FileWriter;
use LC::File;
use Fcntl qw(:seek);

our @ISA = qw (CAF::FileWriter);

=pod

=head1 NAME

CAF::FileEditor - Class for securely making minor changes in CAF
applications.

=head1 DESCRIPTION

This class should be used whenever a file is to be opened for
modifying its existing contents. For instance, if you want to add a
single line at the beginning or the end of the file.

As usual, all operations may be logged by passing a C<log> argument to
the class constructor.

=head2 Public methods

=over

=item new

Returns a new object it accepts the same arguments as the constructor
for C<CAF::FileWriter>

=cut

sub new
{
    my $class = shift;
    my $self = $class->SUPER::new (@_);
    if (-f *$self->{filename}) {
	my $txt = LC::File::file_contents (*$self->{filename});
	$self->IO::String::open ($txt);
	seek($self, 0, SEEK_END);
    }
    return $self;
}

=pod

=item open

Synonym for C<new()>

=cut

sub open
{
    return new(@_);
}

=pod

=item set_contents

Sets the contents of the file to the given argument. Usually, it
doesn't make sense to use this method directly. Just use a
C<CAF::FileWriter> object instead.

=cut

sub set_contents
{
    return IO::String::open (@_);
}

=pod

=item head_print

Appends a line to the very beginning of the file.

=back

=cut

sub head_print
{
    my ($self, $head) = @_;
    my $txt = $self->string_ref();
    $self->set_contents ($head . $$txt);
    return $self;
}

__END__

=pod

=head1 EXAMPLES

=head2 Appending to the end of a file

For instance, you may want to append a line to the end of a file, if
it doesn't exist already:

    my $fh = CAF::FileEditor->open ("/foo/bar",
                                    log => $self);
    if (${$fh->string_ref()} !~ m{hello, world}m) {
        print $fh "hello, world\n";
    }
    $fh->close();

=head2 Cancelling changes in case of error

This is a subclass of C<CAF::FileWriter>, so just do as you did with
it:

    my $fh = CAF::FileEditor->open ("/foo/bar",
                                    log => $self);
    $fh->cancel() if $error;
    $fh->close();

=head2 Appending a line to the beginning of the file

Trivial: use the C<head_print> method:

    my $fh = CAF::FileEditor->open ("/foo/bar",
                                    log => $self);
    $fh->head_print ("This is a nice header for my file");

=head1 SEE ALSO

This is class inherits from L<CAF::FileWriter(3pm)>, and thus from
L<IO::String(3pm)>.

=cut
