package File::AtomicWrite;

use strict;
use warnings;

use version;

# Minimal working version
our $VERSION = 1.18;

=pod

=head1 SYNOPSIS

This is a mock module for File::AtomicWrite.

=head1 DESCRIPTION

This contains backup versions of File::AtomicWrite so that they can be used
for unit testing other modules.

=head2 write_file

Main function used in CAF::FileWriter->close

Sets same C<main::> variables as mocked C<LC::Check> in thi s modules dir.
This is not the ususal C<Test::Quattor> mocking code!.

=over

=item %opts

Mocked options hash that used to be passed to C<LC::Check::file>,
and is very similar to the options attribute.

=item path

Filename that is written to.

=item lc_check_file

A counter that is increased if the counter already exists

Create it in the tests with
    our $lc_check_file = 0;

=item faw_die

If C<$main::faw_die> evalutes to true (so no empty string/undef/0), C<die>
with message C<<File::AtomicWrite C<faw_die>>>.

It can be used to test failures during write.

=back

The old mocked C<$main::file_changed> value is not returned.
Changes to files are now decided via the mocked C<LC::File::file_contents>

Use in tests as
    our $path;
    ...

=cut


sub write_file
{
    my ($self, $kwargs) = @_;

    %main::opts = %$kwargs;
    $main::opts{contents} = ${$kwargs->{input}};
    $main::path = $kwargs->{file};

    $main::lc_check_file++ if defined $main::lc_check_file;

    die "File::AtomicWrite $main::faw_die" if $main::faw_die;
};

1;
