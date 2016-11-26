package LC::File;

use strict;
use warnings;

use LC::Exception qw(throw_error);

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

=item text_from_file

The filename passed to read the contents from.

=item text_throw

If true, throw an error with message C<<file_contents <text_throw>>>.
If C<text_throw> is an arrayref, throw message C<<file_contents <text_throw->[0]>>>
and 2nd argument (reason) C<text_throw->[1]>.

=back

Use in test as
    our $text = 'abc';

=cut

sub file_contents
{
    $main::text_from_file = shift;
    if ($main::text_throw) {
        my ($msg, $reason);

        if (ref($main::text_throw) eq 'ARRAY') {
            $msg = $main::text_throw->[0];
            $reason = $main::text_throw->[1];
        } else {
            $msg = $main::text_throw;
        }

        throw_error("file_contents $msg", $reason);
    };
    if (scalar(@_) == 2) {
        return $main::edition_result;
    } else {
        return $main::text;
    }
}

1;
