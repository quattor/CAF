use strict;
use warnings;

use Test::More;
use Test::MockModule;
use LC::Exception qw (SUCCESS);
use CAF::Log qw($FH $FILENAME);

mkdir('target/test');

my $mock_log = Test::MockModule->new('CAF::Log');
my $mock_fh = Test::MockModule->new('FileHandle');

my ($log, $fh_new, $fh_autoflush, $fh_print, $fh_close);
$mock_fh->mock('autoflush', sub { $fh_autoflush++; });
$mock_fh->mock('close', sub { $fh_close++; });
$mock_fh->mock('print', sub { shift; $fh_print = shift; });

=pod

=head1 SYNOPSIS

Test all methods for C<CAF::Log>

=over

=item _initialize

=cut

is($FILENAME, 'FILENAME', 'Exported FILENAME');
is($FH, 'FH', 'Exported FH');

# test failures
my $ec = LC::Exception::Context->new()->will_store_errors();

ok(!defined(CAF::Log->new('target/test/mylogfail', 'x')), "CAF::Log failure during init returns undef");
is($ec->error->text(), "cannot instantiate class: CAF::Log: *** Bad options for log target/test/mylogfail: x",
   "error raised with invalid option");
$ec->ignore_error();

$mock_fh->mock('new', sub { return; });
ok(!defined(CAF::Log->new('target/test/mylogfail', 'a')), "CAF::Log failure during init returns undef");
like($ec->error->text(),
     qr{^cannot instantiate class: CAF::Log:.*?Open for append target/test/mylogfail},
     "error raised with Filehandle init failure");
$ec->ignore_error();

# test operational

$mock_fh->mock('new', sub {
    my $class = shift;
    $fh_new = shift;
    return bless {}, $class;
                });


$fh_autoflush = 0;
$fh_new = '';
my $fn = "target/test/unittest.log";
$log = CAF::Log->new($fn, 'pat');
isa_ok($log, 'CAF::Log', 'log is a CAF::Log instance');
isa_ok($log, 'CAF::Object', 'CAF::Log is a CAF::Object subclass');

is($log->{FILENAME}, $fn, "FILENAME attr set to log filename");
is($log->{OPTS}, 'pat', 'OPTS attr set with initial options');
is($log->{SYSLOG}, 'unittest', 'Filenames ending with .log get SYSLOG attr set to basename');
is($log->{TSTAMP}, 1, 'presence of t option sets TSTAMP attr to 1');
is($log->{PROCID}, 1, 'presence of p option sets PROCID attr to 1');
isa_ok($log->{FH}, 'FileHandle', 'FH attr is teh Filehandle instance');
is($fh_new, ">> $fn", "Filehandle initialized with append");
is($fh_autoflush, 1, "autoflush set on Filehandle instance");

# make the fn so it can be renamed in w mode
$fn .= ".old";
open(my $oldfh, '>', $fn);
print $oldfh "$fn\n";
close($oldfh);

$fh_autoflush = 0;
$fh_new = '';
$log = CAF::Log->new($fn, 'w');
isa_ok($log, 'CAF::Log', 'log is a CAF::Log instance');

is($log->{FILENAME}, $fn, "FILENAME attr set to log filename");
is($log->{OPTS}, 'w', 'OPTS attr set with initial options');
ok(! defined($log->{SYSLOG}), 'Filenames not ending with .log do not get SYSLOG attr set');
ok(! defined($log->{TSTAMP}), 'absensce of t option does not set TSTAMP attr');
ok(! defined($log->{PROCID}), 'absensce of p option does not set PROCID attr');
isa_ok($log->{FH}, 'FileHandle', 'FH attr is teh Filehandle instance');
is($fh_new, "> $fn", "Filehandle initialized with write");
is($fh_autoflush, 1, "autoflush set on Filehandle instance");
ok(-e "$fn.prev", "write mode renames existing logfiles with .prev extension");

=pod

=item print

=cut

$log->{TSTAMP} = undef;
$log->{PROCID} = undef;
$fh_print = '';
# test print message
$log->print("mymessage");
is($fh_print, 'mymessage', "print calls Filehandle->print");

# set TSTAMP, test TSTAMP?
$log->{TSTAMP} = 1;
$log->{PROCID} = undef;
$fh_print = '';
$log->print("myothermessage_t");
like($fh_print, qr{^\d{4}/\d{2}/\d{2}-\d{2}:\d{2}:\d{2} myothermessage_t$},
     "print with TSTAMP calls Filehandle->print with timestamp prepended");

$log->{TSTAMP} = undef;
$log->{PROCID} = 1;
$fh_print = '';
$log->print("myothermessage_p");
is($fh_print, "[$$] myothermessage_p",
     "print with PROCID calls Filehandle->print with pid prepended");

$log->{TSTAMP} = 1;
$log->{PROCID} = 1;
$fh_print = '';
$log->print("myothermessage_tp");
like($fh_print, qr{^\d{4}/\d{2}/\d{2}-\d{2}:\d{2}:\d{2} \[\d+\] myothermessage_tp$},
     "print with TSTAMP and PROCID calls Filehandle->print with timestamp and pid prepended");

=pod

=item close

=cut

$fh_close = 0;
ok($log->close(), "close returns success on actual close");
is($fh_close, 1, "close calls Filehandle->close");
ok(! defined($log->{FH}), "close undefs the FH attr");

# run close again, should return undef
ok(! defined($log->close()), "close returns undef if already clsoed / missing FH");
is($fh_close, 1, "close on already closed does not call Filehandle->close again");

=pod

=back

=cut

done_testing();
