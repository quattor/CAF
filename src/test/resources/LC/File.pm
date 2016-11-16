package LC::File;

use strict;
use warnings;

=pod

=head1 SYNOPSIS

This is a mocked module for LC::File.

=head1 DESCRIPTION

This contains mocked versions of LC::File::* so that they can be used
for unit testing other modules.

=head2 file_contents

Return following C<main::> variables

=over

=item text

If only one argument is passed (the filename), return C<$main::text>
to mock the contents of the file.

=item edition_result

If 2 arguments are passed, return C<$main::edition_result>.

=back

Use in test as
    our $text = 'abc';

=cut

sub file_contents
{
    if (scalar(@_) == 2) {
        return $main::edition_result;
    } else {
        return $main::text;
    }
}

1;
