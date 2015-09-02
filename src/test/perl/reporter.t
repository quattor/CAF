use strict;
use warnings;

use FindBin qw($Bin);
use lib "$Bin/modules";
use myreporter;

use Test::More;
use Test::MockModule;
use CAF::Log;
use CAF::Reporter;
use LC::Exception qw (SUCCESS);


my ($openlogged, $closelogged, $syssyslogged, $printed, $logged, $syslogged, $reported, $logprinted);


my $syslogmock = Test::MockModule->new('Sys::Syslog');
$syslogmock->mock('syslog', sub { $syssyslogged = \@_;});

my $caflogmock = Test::MockModule->new('CAF::Log');
$caflogmock->mock('print', sub ($$) {shift; $logprinted = \@_; });

my $mock = Test::MockModule->new('CAF::Reporter');
$mock->mock('_print', sub { $printed = \@_;});

# not via syslogmock
$mock->mock('openlog', sub { $openlogged = \@_;});
$mock->mock('closelog', sub { $closelogged = 1;});

=pod

=head1 SYNOPSIS

Test all methods for C<CAF::Reporter>

=over

=item init_reporter / setup_reporter / set_report_logfile

=cut

# initialised correclty

my $init = {
    'VERBOSE' => 0,
    'DEBUGLV' => 0,
    'QUIET' => 0,
    'LOGFILE' => undef,
    'FACILITY' => 'local1',
};

is_deeply($CAF::Reporter::_REP_SETUP, $init, "_REP_SETUP initialsed");

my $myrep = myreporter->new();
isa_ok($myrep, 'myreporter', 'myrep is a myreporter instance');

# shouldn't be called like this, but this shouldn't change anything
$myrep->setup_reporter();

is_deeply($CAF::Reporter::_REP_SETUP, $init,
          "_REP_SETUP not changed with dummy setup_reporter call");

# debug level 0, enable quiet, verbose and set facility
$myrep->setup_reporter(0, 1, 1, 'facility');
is($CAF::Reporter::_REP_SETUP->{'DEBUGLV'}, 0, "Debug level set to 0");
is($CAF::Reporter::_REP_SETUP->{'QUIET'}, 1, "Quiet enabled");
is($CAF::Reporter::_REP_SETUP->{'VERBOSE'}, 1, "Verbose enabled");
is($CAF::Reporter::_REP_SETUP->{'FACILITY'}, 'facility', "Facility set");

$myrep->init_reporter();
is_deeply($CAF::Reporter::_REP_SETUP, $init, "_REP_SETUP re-initialsed");

$myrep->init_reporter();
$myrep->setup_reporter(-1);
is($CAF::Reporter::_REP_SETUP->{'DEBUGLV'}, 0, "Negative debug level set to 0");
is($CAF::Reporter::_REP_SETUP->{'VERBOSE'}, 0, "Verbose not enabled with negative debug level");

$myrep->init_reporter();
$myrep->setup_reporter( 0);
is($CAF::Reporter::_REP_SETUP->{'DEBUGLV'}, 0, "Debug level set to 0");
is($CAF::Reporter::_REP_SETUP->{'VERBOSE'}, 0, "Verbose not enabled with 0 debug level");

$myrep->init_reporter();
$myrep->setup_reporter(2);
is($CAF::Reporter::_REP_SETUP->{'DEBUGLV'}, 2, "Debug level set to 2");
is($CAF::Reporter::_REP_SETUP->{'VERBOSE'}, 1, "Verbose enabled with positive debug level");

$myrep->init_reporter();
# this is not a valid logfile, just a test value
$myrep->set_report_logfile('whatever');
is($CAF::Reporter::_REP_SETUP->{'LOGFILE'}, 'whatever', "LOGFILE set");

=pod

=item log and syslog

=cut

$myrep->init_reporter();
# log always returns success
ok(! defined($CAF::Reporter::_REP_SETUP->{'LOGFILE'}),
   'no LOGFILE defined');
is($myrep->log('something'), SUCCESS, 'log returns SUCCESS when no LOGFILE set');
ok(! defined $myrep->syslog('something'), 'syslog returns undef when no LOGFILE set');

mkdir('target/test');
# this is a .log file, SYSLOG should be set
my $log = CAF::Log->new('target/test/testlog.log', 'a');
ok($log->{SYSLOG}, 'SYSLOG is set for CAF::Log instance');
isa_ok($log, 'CAF::Log', "log is a CAF::Log instance");

$myrep->init_reporter();
$myrep->setup_reporter(0,0,0,'myfacility');
$myrep->set_report_logfile($log);
isa_ok($CAF::Reporter::_REP_SETUP->{LOGFILE}, 'CAF::Log',
       "LOGFILE is a CAF::Log instance");
is($CAF::Reporter::_REP_SETUP->{LOGFILE}->{SYSLOG}, 'testlog',
   "SYSLOG testlog prepend message for LOGFILE");
is($CAF::Reporter::_REP_SETUP->{FACILITY}, 'myfacility',
   "myfacility FACILITY set");

is($myrep->log('something', 'else'), SUCCESS, "log returned success");
is_deeply($logprinted, ["somethingelse\n"], 
          "LOGFILE print method called on log (string concat with newline)");

$closelogged = undef;
ok(! defined($myrep->syslog('myprio', 'syslog', 'set')), "syslog returned undef");
is_deeply($openlogged, ['testlog', 'pid', 'myfacility'], 
          "syslog openlog called with LOGFILE->SYSLOG prepend message, pid option and FACILITY facility");
is($closelogged, 1, 'syslog calls closelog');
is_deeply($syssyslogged, ['myprio', 'syslogset'], 
          'Syslog::syslog called with myprio priority and concatenated arguments as string');

# test the SYSLOG attribute
delete $CAF::Reporter::_REP_SETUP->{LOGFILE}->{SYSLOG};
$openlogged = undef;
ok(! defined($myrep->syslog('myprio', 'syslog', 'not', 'set')), "syslog returned undef");
ok(! defined($openlogged), "openlog not called when SYSLOG attribute of LOGFILE is not set");

# from now on, mock log and syslog
$mock->mock('log', sub { shift; $logged = \@_;});
$mock->mock('syslog', sub { shift; $syslogged = \@_;});

=pod

=item report

=cut

$myrep->init_reporter();
is($CAF::Reporter::_REP_SETUP->{'QUIET'}, 0, "Quiet disabled");
is($myrep->report(1, 2 ,3), SUCCESS,
   "report returns SUCCESS");
is_deeply($printed, ["123\n"], "report prints joined string and newline with quiet disabled");
is_deeply($logged, ['1','2','3'], "report call log with passed args with quiet disabled");

$printed = undef;
# enable quiet
$myrep->setup_reporter(0, 1);
is($CAF::Reporter::_REP_SETUP->{'QUIET'}, 1, "Quiet enabled");
is($myrep->report(4, 5 ,6), SUCCESS,
   "report returns SUCCESS");
ok(! defined($printed), "report does not print with quiet enabled");
is_deeply($logged, ['4','5','6'], "report calls log with passed args and quiet enabled");


# from now on, mock report
$mock->mock('report', sub { shift; $reported = \@_; return SUCCESS;});

=pod

=item info, OK, warn and error

=cut

# restore initial reporter settings
$myrep->init_reporter();

is($myrep->info('hello', 'info'), SUCCESS, 'info returns success');
is_deeply($reported, ['[INFO]  ', 'hello', 'info'], 'info calls report with prefix and args');
is_deeply($syslogged, ['info', 'hello', 'info'], 'info calls syslogs with info priority and args');

is($myrep->OK('hello', 'ok'), SUCCESS, 'OK returns success');
is_deeply($reported, ['[OK]    ', 'hello', 'ok'], 'OK calls report with prefix and args');
is_deeply($syslogged, ['notice', 'hello', 'ok'], 'OK calls syslogs with notice priority and args');

is($myrep->warn('hello', 'warn'), SUCCESS, 'warn returns success');
is_deeply($reported, ['[WARN]  ', 'hello', 'warn'], 'warn calls report with prefix and args');
is_deeply($syslogged, ['warning', 'hello', 'warn'], 'warn calls syslogs with warning priority and args');

is($myrep->error('hello', 'error'), SUCCESS, 'error returns success');
is_deeply($reported, ['[ERROR] ', 'hello', 'error'], 'error calls report with prefix and args');
is_deeply($syslogged, ['err', 'hello', 'error'], 'error calls syslogs with err priority and args');

=pod

=item verbose

=cut

$myrep->init_reporter();
is($CAF::Reporter::_REP_SETUP->{'VERBOSE'}, 0, "Verbose disabled");
$reported = undef;
$syslogged = undef;
is($myrep->verbose('hello', 'verbose', 'disabled'), SUCCESS, 'verbose returns success with verbose disabled');
ok(! defined($reported), 'verbose does not report with verbose disabled');
ok(! defined($syslogged), 'verbose does not syslog with verbose disabled');


$myrep->setup_reporter(0, 0, 1);
is($CAF::Reporter::_REP_SETUP->{'VERBOSE'}, 1, "Verbose enabled");
$reported = undef;
$syslogged = undef;
is($myrep->verbose('hello', 'verbose', 'enabled'), SUCCESS, 'verbose returns success with verbose enabled');
is_deeply($reported, ['[VERB]  ', 'hello', 'verbose', 'enabled'],
          'verbose calls report with prefix and args with verbose enabled');
is_deeply($syslogged, ['notice', 'hello', 'verbose', 'enabled'],
          'verbose calls syslogs with notice priority and args with verbose verbose enabled');

=pod

=item debug

=cut

my $ec = LC::Exception::Context->new()->will_store_errors();

foreach my $lvl (qw(text -1 10 100)) {
    ok(! defined($myrep->debug($lvl, 'hello', 'debug', 'invalid')),
        'invalid debug levels return undef');

    is($ec->error->text(), "debug: first parameter must be integer in [0-9], got $lvl", 
       "error raised with invalid debuglevel");
    $ec->ignore_error();
}

# global lv < level
$myrep->init_reporter();
is($CAF::Reporter::_REP_SETUP->{'DEBUGLV'}, 0, "debuglv 0 set");
$reported = undef;
$syslogged = undef;
is($myrep->debug(1, 'hello', 'debug', 'lv0'), SUCCESS, 'debug1 returns success with debuglv0');
ok(! defined($reported), 'debug1 does not report with debuglv0');
ok(! defined($syslogged), 'debug1 does not syslog with debuglv0');

# equal level
$myrep->setup_reporter(1);
is($CAF::Reporter::_REP_SETUP->{'DEBUGLV'}, 1, "debuglv 1 set");
is($myrep->debug(1, 'hello', 'debug', 'lv1'), SUCCESS, 'debug1 returns success with debuglv1');
is_deeply($reported, ['[DEBUG] ', 'hello', 'debug', 'lv1'],
          'debug calls report with prefix and args with lvl 1 equal debuglv 1');
is_deeply($syslogged, ['debug', 'hello', 'debug', 'lv1'],
          'debug calls syslogs with debug priority and args with lvl 1 equal debuglv 1');

# global lv > level
$myrep->setup_reporter(2);
is($CAF::Reporter::_REP_SETUP->{'DEBUGLV'}, 2, "debuglv 2 set");
is($myrep->debug(1, 'hello', 'debug', 'lv2'), SUCCESS, 'debug1 returns success with debuglv2');
is_deeply($reported, ['[DEBUG] ', 'hello', 'debug', 'lv2'],
          'debug calls report with prefix and args with lvl 1 lower than debuglv 2');
is_deeply($syslogged, ['debug', 'hello', 'debug', 'lv2'],
          'debug calls syslogs with debug priority and args with lvl 1 lower than debuglv 2');


=pod

=back

=cut

done_testing();
