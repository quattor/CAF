# -*- perl -*-
use strict;
use warnings;
use Test::More;
use Test::Quattor;
use CAF::Service;

if (! -f "/bin/systemctl" && ! -f "/sbin/service") {
    plan skip_all => "No supported variants found";
}

=pod

=head1 SYNOPSIS

Test the AUTOLOAD for C<CAF::Service>

=cut

my $srv = CAF::Service->new(['ntpd']);

is(eval{$srv->restart();1;}, 1, "Restart is generated dynamically")
    or diag $@;
can_ok($srv, "restart");
is(eval{$srv->lkjhljh();1;}, undef, "Stupid method still fails");

done_testing();
