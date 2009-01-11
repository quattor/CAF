=pod

=head1 SYNOPSIS

This is a backup module for LC::File.

=head1 DESCRIPTION

This contains backup versions of LC::File::* so that they can be used
for unit testing other modules.

=cut

package LC::File;

use strict;
use warnings;

sub file_contents
{
    if (scalar(@_) == 2) {
	return $main::edition_result;
    } else {
	return $main::text;
    }
}


1;
