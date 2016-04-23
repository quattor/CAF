# ${license-info}
# ${developer-info}
# ${author-info}
# ${build-info}

package CAF::FileEditor;

use strict;
use warnings;
use CAF::FileWriter;
use LC::File;
use Exporter;
use Fcntl qw(:seek);

use CAF::RuleBasedEditor qw(:rule_constants);
use parent qw(CAF::FileWriter Exporter CAF::RuleBasedEditor);
our @EXPORT = qw(BEGINNING_OF_FILE ENDING_OF_FILE);

use constant BEGINNING_OF_FILE => (SEEK_SET, 0);
use constant ENDING_OF_FILE => (SEEK_END, 0);

# internal constants!
use constant IO_SEEK_BEGIN => (0, SEEK_SET);
use constant IO_SEEK_END => (0, SEEK_END);

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

# FileEditor supports reading/editing a file
sub _is_valid_source
{
    my ($self, $fn) = @_;
    return -f $fn;
}


sub new
{
    my $class = shift;
    my $self = $class->SUPER::new (@_);
    if ($self->_is_valid_source(*$self->{filename})) {
        my $txt = LC::File::file_contents (*$self->{filename});
        $self->IO::String::open ($txt);
        $self->seek(IO_SEEK_END);
    }
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

=item seek_begin

Seek to the beginning of the file.

=cut

sub seek_begin
{
    my ($self) = @_;
    $self->seek(IO_SEEK_BEGIN);
}

=pod 

=item seek_end

Seek to the end of the file.

=cut

sub seek_end
{
    my ($self) = @_;
    $self->seek(IO_SEEK_END);
}

=pod

=item replace_lines(re, goodre, newvalue)

Replace any lines matching C<re> but *not* C<goodre> with
C<newvalue>. If there is no match, nothing will be done. For instance,

    $fh->replace(qr(hello.*), qr(hello.*world), 'hello and good bye, world!')

Will replace all lines containing 'hello' but B<not> world by the
string 'hello and good bye, world!'. But if the file contents are

    There was Eru, who in Arda is called Iluvatar

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
    $self->seek_begin();

    while (my $l = <$self>) {
        if ($l =~ $re && $l !~ $goodre) {
            push (@lns, $newvalue);
        } else {
            push (@lns, $l);
        }
    }
    $self->set_contents (join("", @lns));
    $self->seek_end();
}

=pod

=item add_or_replace_sysconfig_lines(key, value, whence)

Replace the C<value> in lines matching the C<key>. If
there is no match, a new line will be added to the where C<whence> 
and C<offset> tells us.
The sysconfig_separator value can be changed if it's not the usual '='.

=cut


sub add_or_replace_sysconfig_lines {
    my ($self, $key, $value, $whence, $offset) = @_;

    ($offset, $whence) = IO_SEEK_END if (not defined($whence)); 
    $offset = 0 if (not defined($offset)); 

    $self->add_or_replace_lines('^/s*'.$key.'/s*'.SYSCONFIG_SEPARATOR,
                                '^'.$key.'/s*'.SYSCONFIG_SEPARATOR.'/s*'.$value,
                                $key.SYSCONFIG_SEPARATOR.$value."\n", 
                                $whence, $offset);
}

=pod

=item add_or_replace_lines(re, goodre, newvalue, whence, offset, add_after_newline)

Replace lines matching C<re> but not C<goodre> with C<newvalue>. If
there is no match, a new line will be added where the C<whence>
and C<offset> tell us. See C<IO::String::seek> 
for details; e.g. use the constants tuple 
BEGINNING_OF_FILE or ENDING_OF_FILE.
If C<add_after_newline> is true or undef, before adding the new line,
it is verified that a newline precedes this position. If no newline
char is found, one is added first.

C<whence> must be one of SEEK_SET, SEEK_CUR or SEEK_END; 
everything else will be ignored (an error is logged if 
logging is set)). 

Reminder: if the offset position lies beyond SEEK_END, padding will 
occur with $self->pad, which defaults to C<\0>.

=cut

sub add_or_replace_lines
{
    my ($self, $re, $goodre, $newvalue, $whence, $offset, $add_after_newline) = @_;

    $offset = 0 if (not defined($offset)); 
    $add_after_newline = 1 if (not defined($add_after_newline));

    if (*$self->{LOG}) {
        my $fname = *$self->{'filename'};
        my $nv = $newvalue;
        chop $nv;
        *$self->{LOG}->debug (5, "add_or_replace_lines ($fname):",
                                 " re = '$re'\tgoodre = '$goodre'",
                                 " newvalue = '$nv'",
                                 " whence = '$whence'",
                                 " offset = '$offset'",
                                 " add_after_newline = '$add_after_newline'",
                                 );
    }
    my $add = 1;
    my @lns;
    
    my $cur_pos=$self->pos;
    $self->seek (IO_SEEK_BEGIN);
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
        if ($whence == SEEK_SET || $whence == SEEK_CUR || $whence == SEEK_END) { 
            # seek to proper position
            if ($whence == SEEK_CUR) {
                # restore position only relevant for SEEK_CUR
                $self->seek ($cur_pos, SEEK_SET);
            }

            $self->seek ($offset, $whence);

            # new current position
            my $new_cur_pos = $self->pos;
            
            # read in all remaining text
            my $remainder = join('', <$self>);

            my $print_newline;
            # if $new_cur_pos is begin of file, no need to check/insert newline
            if ($add_after_newline && $new_cur_pos) {
                $self->seek ($new_cur_pos - 1, SEEK_SET);
                my $buf = "";
                read($self, $buf, 1);
                $print_newline = ($buf ne "\n") && (substr($newvalue, 0, 1) ne "\n");
                *$self->{LOG}->debug (5, "add_or_replace_lines: inserting newline: $print_newline")
                    if *$self->{LOG};
            }

            # seek to position and insert text
            $self->seek ($new_cur_pos, SEEK_SET);
            print $self "\n" if $print_newline;
            print $self $newvalue;
            print $self $remainder;
        } elsif (*$self->{LOG}) {
            *$self->{LOG}->error ("Wrong whence $whence");
        }
    } else {
        $self->set_contents (join ("", @lns));
    }
    $self->seek_end();
}


=pod

=item get_all_positions(regex, whence, offset)

Return reference to the arrays with the positions 
before and after all matches of the compiled regular expression 
C<regex>, starting from C<whence> (default 
beginning) and C<offset> (default 0). (If the regexp 
does not match, references to empty arrays are returned).

Global regular expression matching is performed (i.e. C<m/$regex/g>). 
The text is searched without line-splitting, but multiline regular 
expressions like C<qr{^something.*$}m> can be used for per line matching.

=cut

sub get_all_positions
{
    my ($self, $regex, $whence, $offset) = @_;

    ($offset, $whence) = IO_SEEK_BEGIN if (not defined($whence)); 
    $offset = 0 if (not defined($offset)); 
    
    my $cur_pos = $self->pos;

    my @before = ();
    my @after = ();

    if ($whence == SEEK_SET || $whence == SEEK_CUR || $whence == SEEK_END) { 
        $self->seek($offset, $whence);

        my $remainder = join('', <$self>);

        # This has to be global match, otherwise this becomes 
        # an infinite loop if there is a match
        while ($remainder =~ /$regex/g) {
            push(@before, $-[0]);
            push(@after, $+[0]+1);
        }
        
        # restore original position
        $self->seek ($cur_pos, SEEK_SET);
    } elsif (*$self->{LOG}) {
        *$self->{LOG}->error ("Wrong whence $whence");
    }

    return (\@before, \@after);    
}


=pod

=item get_header_positions(regex, whence, offset)

Return the position before and after the "header".
A header is a block of lines that start with same 
compiled regular expression C<regex>. 
Default value for C<regex> is C<qr{^\s*#.*$}m>
(matching a block of text with each line starting with a C<#>); 
the default value is also used when C<regex> is C<undef>. 
C<(-1, -1)> is returned if no match was found.

C<whence> and C<offset> are passed to underlying C<get_all_positions>
call.

=cut

sub get_header_positions
{
    my ($self, $regex, $whence, $offset) = @_;

    $regex = qr{^\s*#.*$}m if (not defined($regex));
    my ($before, $after) = $self->get_all_positions($regex, $whence, $offset);

    my ($start, $end)= (-1, -1);
    
    my $matches = scalar @$before;
    if ($matches) {
        # start is the first match
        $start = $before->[0];

        for my $i (0..$matches-1){
            # the "after" position is the beginning of the next line
            if ($end == -1 || $before->[$i] == $end) {
                $end=$after->[$i];
            } else {
                last;
            };
        };
    }

    return $start, $end;
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
    $self->seek_begin();

    while (my $l = <$self>) {
        unless ($l =~ $re && $l !~ $goodre) {
            push (@lns, $l);
        }
    }
    $self->set_contents(join("", @lns));
    $self->seek_end();
}

__END__

=pod

=back

=head1 EXPORTED CONSTANTS

The following constants are automatically exported when using this module:

=over

=item C<BEGINNING_OF_FILE>

Flag to pass to C<add_or_replace_lines>. Lines should be added at the
beginning of the file. (To be used in list context, as this is actually 
C<(SEEK_SET, 0)>.)

=item C<ENDING_OF_FILE>

Flag to pass to C<add_or_replace_lines>. Lines should be added at the
end of the file. (To be used in list context, as this is actually 
C<(SEEK_END, 0)>.)

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

This class inherits from L<CAF::FileWriter(3pm)>, and thus from
L<IO::String(3pm)>.

=cut
