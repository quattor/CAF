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
use Exporter;
use Fcntl qw(:seek);

our @ISA = qw (CAF::FileWriter Exporter);
our @EXPORT = qw(BEGINNING_OF_FILE ENDING_OF_FILE);

use constant BEGINNING_OF_FILE => SEEK_SET;
use constant ENDING_OF_FILE => SEEK_END;
use constant SYSCONFIG_SEPARATOR => '=';

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

=cut

sub head_print
{
    my ($self, $head) = @_;
    my $txt = $self->string_ref();
    $self->set_contents ($head . $$txt);
    return $self;
}

=pod

=item replace_lines(re, goodre, newvalue)

Replace any lines matching C<re> but *not* C<goodre> with
C<newvalue>. If there is no match, nothing will be done. For instance,

    $fh->replace(qr(hello.*), qr(hello.*world), 'hello and good bye, world!')

Will replace all lines containing 'hello' but B<not> world by the
string 'hello and good bye, world!'. But if the file contents are

    There was Eru, who in Arda is called IlÃºvatar

it will be kept as is.

This is useful when we want to change a given configuration directive
only if it exists and it's wrong.

The regular expressions can be expressed with the C<qr> operator, thus
allowing for modification flags such as C<i>.

=cut

sub replace_lines
{
    my ($self, $re, $goodre, $newvalue) = @_;

    my @lns;
    seek($self, 0, SEEK_SET);

    while (my $l = <$self>) {
	if ($l =~ $re && $l !~ $goodre) {
	    push (@lns, $newvalue);
	} else {
	    push (@lns, $l);
	}
    }
    $self->set_contents (join("", @lns));
    seek ($self, 0, SEEK_END);
}

=pod

=item add_or_replace_sysconfig_lines(key, value, whence)

Replace the C<value> in lines matching the C<key>. If
there is no match, a new line will be added to the where C<whence> tells us.
The sysconfig_separator value can be changed if it's not the usual '='.

=cut


sub add_or_replace_sysconfig_lines {
    my ($self, $key, $value, $whence) = @_;

    if (not defined($whence)) { $whence = ENDING_OF_FILE;}
    $self->add_or_replace_lines($key, $key.'/s*'.SYSCONFIG_SEPARATOR.'/s*'.$value,
                        $key.'='.$value."\n", $whence);
}

=pod

=item add_or_replace_lines(re, goodre, newvalue, whence)

Replace lines matching C<re> but not C<goodre> with C<newvalue>. If
there is no match, a new line will be added to the where C<whence>
tells us.

=cut

sub add_or_replace_lines
{
    my ($self, $re, $goodre, $newvalue, $whence) = @_;

    if (*$self->{LOG}) {
        my $fname = *$self->{'filename'};
        my $nv = $newvalue;
        chop $nv;
        *$self->{LOG}->debug (5, "add_or_replace_lines ($fname): re = '$re'\tgoodre = '$goodre'\tnewvalue = '$nv'\twhence = '$whence'");
    }
    my $add = 1;
    my @lns;
    seek ($self, 0, SEEK_SET);
    while (my $l = <$self>) {
	if ($l =~ $re) {
	    if ($l =~ $goodre) {
		push (@lns, $l);
	    } else {
		push (@lns, $newvalue);
	    }
	    $add = 0;
	} else {
	    push (@lns, $l);
	}
    }

    if ($add) {
	if ($whence == BEGINNING_OF_FILE) {
	    $self->head_print ($newvalue);
	} elsif ($whence == ENDING_OF_FILE) {
	    print $self $newvalue;
	} elsif (*$self->{LOG}) {
	    *$self->{LOG}->error ("Wrong whence value");
	}
    } else {
	$self->set_contents (join ("", @lns));
    }
    seek ($self, 0, SEEK_END);
}


=pod

=item remove_lines(re, goodre)

Remove any lines matching C<re> but *not* C<goodre>.
If there is no match, nothing will be done.

=cut

sub remove_lines
{
    my ($self, $re, $goodre) = @_;

    if (*$self->{LOG}) {
        my $fname = *$self->{'filename'};
        *$self->{LOG}->debug (5, "remove_lines ($fname): re = '$re'\tgoodre = '$goodre'");
    }
    my @lns;
    seek($self, 0, SEEK_SET);

    while (my $l = <$self>) {
        unless ($l =~ $re && $l !~ $goodre) {
            push (@lns, $l);
        }
    }
    $self->set_contents(join("", @lns));
    seek($self, 0, SEEK_END);
}

__END__

=pod

=head1 EXPORTED CONSTANTS

The following constants are automatically exported when using this module:

=over

=item C<BEGINNING_OF_FILE>

Flag to pass to C<add_or_replace_lines>. Lines should be added at the
beginning of the file.

=item C<ENDING_OF_FILE>

Flag to pass to C<add_or_replace_lines>. Lines should be added at the
end of the file.

=back

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

=head2 Replacing configuration lines

If you want to replace existing lines:

    my $fh = CAF::FileEditor->open ("/foo/bar",
                                    log => $self);
    $fh->replace_lines (qr(pam_listfile),
                        qr(session\s+required\s+pam_listfile.so.*item=user),
                        join("\t", qw(session required pam_listfile.so
                                      onerr=fail item=user sense=allow
                                      file=/some/acl/file)));

This will B<not> add any new lines in case there are no matches.

=head2 Adding or replacing lines

If you want to replace lines that match a given regular expression,
and have to add them to the beginning of the file in case there are no
matches:

    my $fh = CAF::FileEditor->open ("/foo/bar",
                                    log => $self);
    $fh->add_or_replace_lines (qr(pam_listfile),
                        qr(session\s+required\s+pam_listfile.so.*item=user),
                        join("\t", qw(session required pam_listfile.so
                                      onerr=fail item=user sense=allow
                                      file=/some/acl/file)),
                        BEGINNING_OF_FILE);

=head1 SEE ALSO

This is class inherits from L<CAF::FileWriter(3pm)>, and thus from
L<IO::String(3pm)>.

=cut
