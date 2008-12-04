=pod

=head1 SYNOPSIS

Backup module emulating LC::Check, for CAF::Tests

=head1 DESCRIPTION

When testing CAF modules, we don't care about files being created or
not. All CAF wrappers do is to call the appropriate LC::* function,
with a set of arguments, and we just need to be sure that the correct
arguments are passed.

Functions on this module just save their arguments on some global
variable on main package. This way, tests can check the correctness of
the calls, without worrying to set up any special environment for
tests.

=cut

package LC::Check;

sub file
{
    my ($path, %opts) = @_;
    $main::path = $path;
    %main::opts = %opts;
    $main::lc_check_file++ if defined $main::lc_check_file;
    return $main::file_changed;
}

1;
