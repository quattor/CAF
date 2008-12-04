=pod

=head1 SYNOPSIS

Backup functions, mainly for testing CAF::Process

=head1 DESCRIPTION

Functions on this module just save their arguments somewhere on the
main package, and increment a counter for allowing the test
application to check what function was actually called.

=cut


package LC::Process;

# Backup methods, I don't want any commands to actually run. I'm not
# testing LC!!

sub run
{
    my @cmd = @_;
    $main::cmd = \@cmd;
    $main::run++;
}

sub execute
{
    my ($cmd, %opts) = @_;
    $main::cmd = $cmd;
    $main::execute++;
    %main::opts = %opts;
}

sub output
{
    my @cmd = @_;
    $main::cmd = \@cmd;
    $main::output++;
}

sub trun
{
    my ($timeout, @cmd) = @_;
    $main::cmd = \@cmd;
    $main::trun++;
}

sub toutput
{
    my ($timeout, @cmd) = @_;
    $main::cmd = \@cmd;
    $main::toutput++;
}

1;
