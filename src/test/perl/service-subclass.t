use strict;
use warnings;
use Test::More;

use Test::MockModule;
use CAF::Service qw(FLAVOURS);
use FindBin qw($Bin);
use lib "$Bin/modules";

use myservice;

use Test::Quattor::Object;

#TODO: fixed in newer buildtools

# Cannot use Test::Quattor, as it calls 
# set_service_variant, and it overrides the AUTOLOAD

# CAF::Service _logcmd uses execute()
my $command;
my $mockp = Test::MockModule->new('CAF::Process');
$mockp->mock('execute', sub { 
    my $self = shift;
    $command = join(" ", @{$self->{COMMAND}});
    return 1;
});

my $mocks = Test::MockModule->new('CAF::Service');
$mocks->mock('os_flavour', 'linux_sysv');


my $obj = Test::Quattor::Object->new();

my $srv = myservice->new(log=>$obj);

=head2 Test methods

Test avaliable methods

=cut

foreach my $m (qw(start stop restart reload init)) {
    foreach my $fl (FLAVOURS) {
        my $method = "${m}_${fl}";
        diag "can $method";
        ok($srv->can($method), "Method $method found");
    }
}

=pod

=head2 Test systemd

Test all methods + custom init for C<CAF::Service> for linux_sysv

=cut

foreach my $m (qw(start stop restart reload init)) {
    diag "method $m";
    $srv->$m();
    is($command, "service myservice $m", "subclassed service myservice $m works");
}

# for stop, the subclassed stop should have been called
ok($srv->{mystop}, 'Subclassed stop was called');

done_testing();
