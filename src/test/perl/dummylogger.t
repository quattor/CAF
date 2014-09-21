# -*- perl -*-
use strict;
use warnings;
use Test::More;
use Test::Quattor;
use CAF::DummyLogger;
use Test::MockModule;

=pod

=head1 SYNOPSIS

Test all methods for C<CAF::DummyLogger>

=cut


my $log = CAF::DummyLogger->new();
isa_ok ($log, "CAF::DummyLogger", "Correct class after new method");
ok(!defined($log->error('something')), "Fake logger with error method initialised");
ok(!defined($log->warn('something')), "Fake logger with warn method initialised");
ok(!defined($log->info('something')), "Fake logger with info method initialised");
ok(!defined($log->verbose('something')), "Fake logger with verbose method initialised");
ok(!defined($log->debug(1, 'something')), "Fake logger with debug method initialised");

done_testing();
