#${PMpre} CAF::FileReader${PMpost}

use base qw(CAF::FileEditor);

=pod

=head1 NAME

CAF::FileReader - Class for only reading files in CAF applications.

=head1 DESCRIPTION

Normal use:

  use CAF::FileReader;
  my $fh = CAF::FileReader->open ("my/path");
  while (my $line = <$fh>) {
     # Do something
  }

This class should be used whenever a file is to be opened for reading,
and no modifications are expected.

Printing to this file is allowed, but changes will be discarded (in
effect, the C<FileEditor> is C<cancel>-ed.

=over

=item new

Create a new instance: open the file C<$fn>, read it,
seek to the beginning and C<cancel> any (future) changes.

=cut

# FileReader supports reading a file or pipe
sub _is_valid_file
{
    my ($self, $fn) = @_;
    return -f $fn || -p $fn;
}

sub new
{
    my ($class, @opts) = @_;

    my $self = $class->SUPER::new(@opts);

    $self->seek_begin();

    $self->cancel(msg => 'reading with '.ref($self));
    return $self;
}

=item open

Synonym for C<new()>

=cut

# Alias open to new.
no warnings 'redefine';
*open = \&new;
use warnings;

sub reopen
{
    my $self = shift;

    $self->SUPER::reopen();

    $self->seek_begin();

    $self->cancel(msg => 'reading with '.ref($self));
}

=back

=cut

1;
