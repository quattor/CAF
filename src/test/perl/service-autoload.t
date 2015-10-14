# -*- perl -*-
use strict;
use warnings;
use Test::More;
use CAF::Service;
use Test::MockModule;

# do not use Test::Quattor for this test

my $mock = Test::MockModule->new("CAF::Service");
$mock->mock("os_flavour", "linux_systemd");

# CAF::Service _logcmd uses execute()
my $command;
my $mockp = Test::MockModule->new('CAF::Process');
$mockp->mock('execute', sub {
    my $self = shift;
    $command = join(" ", @{$self->{COMMAND}});
    return 1;
});

=pod

=head1 SYNOPSIS

Test the AUTOLOAD for C<CAF::Service>

=cut

my $srv = CAF::Service->new(['ntpd']);

is(eval{$srv->restart();1;}, 1, "Restart is generated dynamically")
    or diag $@;
ok(! $srv->can("restart"), 'After AUTOLOADING, the method is not added to the namespace (always re-AUTOLOADed)');
is(eval{$srv->lkjhljh();1;}, undef, "Stupid method still fails");

done_testing();
