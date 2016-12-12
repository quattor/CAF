use strict;
use warnings;

use FindBin qw($Bin);
use lib "$Bin/modules";
use myreporter;
use myreportermany;

use Test::More;
use Test::MockModule;
use CAF::Log;
use CAF::Reporter qw($VERBOSE
    $DEBUGLV $QUIET $LOGFILE
    $SYSLOG $FACILITY $HISTORY
    $WHOAMI $VERBOSE_LOGFILE
    $STRUCT
);
use LC::Exception qw (SUCCESS);

use Scalar::Util qw(refaddr);

use Readonly;
Readonly my $EVENTS => 'EVENTS';
Readonly my $INSTANCES => 'INSTANCES';

use object_ok;

mkdir('target/test');

my ($openlogged, $closelogged, $syssyslogged,
    $printed, $logged, $syslogged, $reported,
    $logprinted, $struct);


my $syslogmock = Test::MockModule->new('Sys::Syslog');
$syslogmock->mock('syslog', sub { $syssyslogged = \@_;});

my $caflogmock = Test::MockModule->new('CAF::Log');
$caflogmock->mock('print', sub ($$) {shift; $logprinted = \@_; });

my $mock = Test::MockModule->new('CAF::Reporter');
$mock->mock('_print', sub { $printed = \@_;});
$mock->mock('_struct_teststruct', sub {shift; $struct = \@_;});

# not via syslogmock
$mock->mock('openlog', sub { $openlogged = \@_;});
$mock->mock('closelog', sub { $closelogged = 1;});

=pod

=head1 SYNOPSIS

Test all methods for C<CAF::Reporter>

=over

=item init_reporter / _rep_setup / config_reporter / init_logfile

=cut

# test exported constants

# initialised correclty
is($VERBOSE, 'VERBOSE', 'expected value for readonly $VERBOSE');
is($DEBUGLV, 'DEBUGLV', 'expected value for readonly $DEBUGLV');
is($QUIET, 'QUIET', 'expected value for readonly $QUIET');
is($LOGFILE, 'LOGFILE', 'expected value for readonly $LOGFILE');
is($SYSLOG, 'SYSLOG', 'expected value for readonly $SYSLOG');
is($FACILITY, 'FACILITY', 'expected value for readonly $FACILITY');
is($HISTORY, 'HISTORY', 'expected value for readonly $HISTORY');
is($WHOAMI, 'WHOAMI', 'expected value for readonly $WHOAMI');
is($VERBOSE_LOGFILE, 'VERBOSE_LOGFILE', 'expected value for readonly $VERBOSE_LOGFILE');
is($STRUCT, 'STRUCT', 'expected value for readonly $STRUCT');

my $init = {
    $VERBOSE => 0,
    $DEBUGLV => 0,
    $QUIET => 0,
    $LOGFILE => undef,
    $FACILITY => 'local1',
    $VERBOSE_LOGFILE => 0,
    $STRUCT => undef,
};

is_deeply($CAF::Reporter::_REP_SETUP, $init, "_REP_SETUP initialsed");

my $myrep = myreporter->new();
isa_ok($myrep, 'myreporter', 'myrep is a myreporter instance');

# shouldn't be called like this, but this shouldn't change anything
$myrep->config_reporter();

is_deeply($CAF::Reporter::_REP_SETUP, $init,
          "_REP_SETUP not changed with dummy config_reporter call");

# debug level 0, enable quiet, verbose, set facility and verbose_logfile
$myrep->config_reporter(
    debuglvl => 0,
    quiet => 1,
    verbose => 1,
    facility => 'facility',
    verbose_logfile => 1,
    logfile => 'not an actual log instance',
    struct => 'teststruct',
);
is($CAF::Reporter::_REP_SETUP->{$DEBUGLV}, 0, "Debug level set to 0");
is($CAF::Reporter::_REP_SETUP->{$QUIET}, 1, "Quiet enabled");
is($CAF::Reporter::_REP_SETUP->{$VERBOSE}, 1, "Verbose enabled");
is($CAF::Reporter::_REP_SETUP->{$FACILITY}, 'facility', "Facility set");
is($CAF::Reporter::_REP_SETUP->{$VERBOSE_LOGFILE}, 1, "verbose_logfile set");
is($CAF::Reporter::_REP_SETUP->{$LOGFILE}, 'not an actual log instance', "logfile set");
is($CAF::Reporter::_REP_SETUP->{$STRUCT}, "_struct_teststruct", "struct set");
is($CAF::Reporter::_REP_SETUP, $myrep->_rep_setup(), "_rep_setup returns ref to _REP_SETUP for Reporter");

is($myrep->get_debuglevel(), 0, "Returned debug level 0");
ok($myrep->is_quiet(), "is quiet");
ok($myrep->is_verbose(), "is verbose");

$myrep->init_reporter();
is_deeply($CAF::Reporter::_REP_SETUP, $init, "_REP_SETUP re-initialsed");

$myrep->init_reporter();
$myrep->config_reporter(debuglvl => -1);
is($CAF::Reporter::_REP_SETUP->{$DEBUGLV}, 0, "Negative debug level set to 0");
is($CAF::Reporter::_REP_SETUP->{$VERBOSE}, 0, "Verbose not enabled with negative debug level");

ok(! $myrep->is_verbose(), "is not verbose");

$myrep->init_reporter();
$myrep->config_reporter(debuglvl => 0);
is($CAF::Reporter::_REP_SETUP->{$DEBUGLV}, 0, "Debug level set to 0");
is($CAF::Reporter::_REP_SETUP->{$VERBOSE}, 0, "Verbose not enabled with 0 debug level");


$myrep->init_reporter();
$myrep->config_reporter(debuglvl => 2);
is($CAF::Reporter::_REP_SETUP->{$DEBUGLV}, 2, "Debug level set to 2");
is($CAF::Reporter::_REP_SETUP->{$VERBOSE}, 1, "Verbose enabled with positive debug level");

$myrep->init_reporter();
# this is not a valid logfile, just a test value
$myrep->config_reporter(logfile => 'whatever');
is($CAF::Reporter::_REP_SETUP->{$LOGFILE}, 'whatever', "LOGFILE set");

$myrep->init_logfile('target/test/test_init_logfile.log', 'a');
my $initlogfile = $CAF::Reporter::_REP_SETUP->{$LOGFILE};
isa_ok($initlogfile, 'CAF::Log', "new LOGFILE set");
is($initlogfile->{FILENAME}, 'target/test/test_init_logfile.log', "new LOGFILE filename set");
is($initlogfile->{OPTS}, 'a', "new LOGFILE options set");

# test preservation with undefs
$myrep->init_reporter();
$myrep->config_reporter(debuglvl => 2, quiet => 1, verbose => 1, facility => 'facility');

is($myrep->get_debuglevel(), 2, "Returned debug level 2");
ok($myrep->is_quiet(), "is quiet");
ok($myrep->is_verbose(), "is verbose");


$myrep->config_reporter(logfile => 'whatever');
my $current = { %$CAF::Reporter::_REP_SETUP };
$myrep->config_reporter();
is_deeply($CAF::Reporter::_REP_SETUP, $current,
   "passing noargs to config_reporter preserves the settings");

$myrep->config_reporter(
    debuglvl => undef,
    quiet => undef,
    verbose => undef,
    facility => undef,
    verbose_logfile => undef,
    logfile => undef,
    struct => undef,
);
is_deeply($CAF::Reporter::_REP_SETUP, $current,
   "passing undefs to config_reporter preserves the settings");

$myrep->init_reporter();
$printed = undef;
ok($myrep->config_reporter(struct => 'teststruct'), 'setting struct retruns success');
is($CAF::Reporter::_REP_SETUP->{$STRUCT}, "_struct_teststruct", "struct set 2");
ok($myrep->config_reporter(struct => 0), 'unsetting struct with false value retruns success');
ok(! defined($CAF::Reporter::_REP_SETUP->{$STRUCT}), "struct unset");
ok($myrep->config_reporter(struct => 'teststruct'), 'setting struct retruns success 2');
is($CAF::Reporter::_REP_SETUP->{$STRUCT}, "_struct_teststruct", "struct set 3");
ok(!defined($myrep->config_reporter(struct => 'novalidstruct')), 'try to setting invalid struct retruns undef');
is_deeply($printed,
          ["[ERROR] No method _struct_novalidstruct found for structured logging\n"],
          "error message reported with invalid struct");
is($CAF::Reporter::_REP_SETUP->{$STRUCT}, "_struct_teststruct", "struct not modified on failure");


=item _make_message_string

=cut

sub mms {return CAF::Reporter::_make_message_string(@_)};

use utf8;
is(mms("begin", undef, "testutf8_☺_", "test_binary_\0_\0\0", "\nnext\t ","end"),
   "begin<undef>testutf8_☺_test_binary_?_??\nnext\t end",
   "_make_message_string handles undef, utf8 and non-utf8 code (in proper encoding)");
no utf8;

# U+263A (the smiley) is now used in non-utf8 encoding, so it's binary garbage
# the smiley is 3 bytes (0xE2 0x98 0xBA)
is(mms("testutf8_☺_"),
   "testutf8_???_",
   "_make_message_string via :print: charclass is encoding aware");

#
# test templating with hashrefs
#
my $warn;
$SIG{__WARN__} = sub {$warn = $_[0];};

$warn = undef;
is(mms("Hello [% world %]", {world => 'quattor'}),
   "Hello quattor",
   "TT based templating triggered by hashref as last element");
ok(!defined($warn), "no warn on success");

$warn = undef;
is(mms("Hello world", {world => 'quattor'}),
   "Hello world",
   "TT based templating success w/o any templating");
ok(!defined($warn), "no warn on success w/o templating");

$warn = undef;
is(mms("Hello [% world %]", {worldz => 'quattorz'}),
   "Unable to process template 'Hello [% world %]' with data {'worldz' => 'quattorz'}: var.undef error - undefined variable: world",
   "Nothing to template, strict mode");
like($warn, qr{Unable to process template .* undefined variable: world}, "warn on nothing to template");

$warn = undef;
is(mms("Hello [% IF world %] missing end", {world => 'quattor'}),
   "Unable to process template 'Hello [% IF world %] missing end' with data {'world' => 'quattor'}: file error - parse error - input text line 1: unexpected end of input",
   "Invalid template failure");
like($warn, qr{Unable to process template .* parse error}, "warn on invalid template");

$warn = undef;
is(mms({world => 'quattor'}),
   "{'world' => 'quattor'}",
   "special case with only hashref and no template passed");
ok(!defined($warn), "no warn on success without template");

=item log and syslog

=cut

$myrep->init_reporter();
# log always returns success
ok(! defined($CAF::Reporter::_REP_SETUP->{$LOGFILE}),
   'no LOGFILE defined');
is($myrep->log('something'), SUCCESS, 'log returns SUCCESS when no LOGFILE set');
ok(! defined $myrep->syslog('something'), 'syslog returns undef when no LOGFILE set');

# this is a .log file, SYSLOG should be set
my $log = CAF::Log->new('target/test/testlog.log', 'a');
ok($log->{SYSLOG}, 'SYSLOG is set for CAF::Log instance');
isa_ok($log, 'CAF::Log', "log is a CAF::Log instance");

$myrep->init_reporter();
$myrep->config_reporter(debuglvl => 0, quiet => 0, verbose => 0, facility => 'myfacility', logfile => $log);
$struct = undef;
isa_ok($CAF::Reporter::_REP_SETUP->{LOGFILE}, 'CAF::Log',
       "LOGFILE is a CAF::Log instance");
is($CAF::Reporter::_REP_SETUP->{LOGFILE}->{SYSLOG}, 'testlog',
   "SYSLOG testlog prepend message for LOGFILE");
is($CAF::Reporter::_REP_SETUP->{FACILITY}, 'myfacility',
   "myfacility FACILITY set");

# No templating
is($myrep->log('something', 'else', {a => 1}), SUCCESS, "log returned success");
is_deeply($logprinted, ["somethingelse\n"],
          "LOGFILE print method called on log (string concat with newline)");
ok(! defined($struct), "no struct logging without STRUCT set");

$myrep->config_reporter(struct => 'teststruct');
is($myrep->log('[% a %]something', 'else', {a => 1}), SUCCESS, "log returned success 2");
is_deeply($logprinted, ["1somethingelse\n"],
          "LOGFILE print method called on log (string concat with newline and templating) 2");
is_deeply($struct, [{a => 1}],
          "struct logging called with STRUCT set and hasref as last element");

$struct = undef;
is($myrep->log('[% a %]something', 'else'), SUCCESS, "log returned success 3");
is_deeply($logprinted, ["[% a %]somethingelse\n"],
          "LOGFILE print method called on log (string concat with newline and no templating) 3");
ok(! defined($struct), "no struct logging with STRUCT set and w/o hashref as last element");


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

# from now on, mock syslog
my $previoussyslogged;
$mock->mock('syslog', sub { shift; $previoussyslogged = $syslogged; $syslogged = \@_;});

=item _struct_CEEsyslog / struct CEEsyslog

=cut


$myrep->init_reporter();

$myrep->_struct_CEEsyslog({a => 1, b => { c => [0]} });
is_deeply($syslogged, ['info', '@cee: ', '{"a":1,"b":{"c":[0]}}'],
          '_struct_CEEsyslog calls syslogs with info priority and @cee and jsonencoded data');

$myrep->init_reporter();
ok($myrep->config_reporter(struct => 'CEEsyslog', verbose => 1),
   'CEEsyslog struct logging selected');
ok($myrep->verbose('[% b.c.0 %] something with [% a %]', {a => 2, b => { c => [1,2,3]} }),
   'verbose reported CEEsyslog');

# check reported via print
is_deeply($printed, ["[VERB] 1 something with 2\n"],
          'verbose calls report/_print with templated data');
# check double syslog, first/previous syslog call, 2nd/last syslog via CEEsyslog via log
is_deeply($previoussyslogged, ['notice', '[% b.c.0 %] something with [% a %]', {a => 2, b => { c => [1,2,3]} }],
          'verbose with all args untemplated data to syslog');
# it is important that integers are preserved
is_deeply($syslogged, ['info', '@cee: ', '{"a":2,"b":{"c":[1,2,3]}}'],
          'verbose with struct CEEsyslog');


# from now on, mock log
$mock->mock('log', sub { shift; $logged = \@_; return SUCCESS});

=pod

=item report

=cut

$myrep->init_reporter();
is($CAF::Reporter::_REP_SETUP->{$QUIET}, 0, "Quiet disabled");
is($myrep->report(1, 2 ,3), SUCCESS,
   "report returns SUCCESS");
is_deeply($printed, ["123\n"], "report prints joined string and newline with quiet disabled");
is_deeply($logged, ['1','2','3'], "report call log with passed args with quiet disabled");

$printed = undef;
# enable quiet
$myrep->config_reporter(debuglvl => 0, quiet => 1);
is($CAF::Reporter::_REP_SETUP->{$QUIET}, 1, "Quiet enabled");
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
is_deeply($reported, ['[INFO] ', 'hello', 'info'], 'info calls report with prefix and args');
is_deeply($syslogged, ['info', 'hello', 'info'], 'info calls syslogs with info priority and args');

is($myrep->OK('hello', 'ok'), SUCCESS, 'OK returns success');
is_deeply($reported, ['[OK]   ', 'hello', 'ok'], 'OK calls report with prefix and args');
is_deeply($syslogged, ['notice', 'hello', 'ok'], 'OK calls syslogs with notice priority and args');

is($myrep->warn('hello', 'warn'), SUCCESS, 'warn returns success');
is_deeply($reported, ['[WARN] ', 'hello', 'warn'], 'warn calls report with prefix and args');
is_deeply($syslogged, ['warning', 'hello', 'warn'], 'warn calls syslogs with warning priority and args');

is($myrep->error('hello', 'error'), SUCCESS, 'error returns success');
is_deeply($reported, ['[ERROR] ', 'hello', 'error'], 'error calls report with prefix and args');
is_deeply($syslogged, ['err', 'hello', 'error'], 'error calls syslogs with err priority and args');

=pod

=item set_report_history / init_history / event

=cut

my $obj = object_ok->new();

ok(! defined($myrep->{$HISTORY}), 'No HISTORY by default');
ok($myrep->event($obj), 'event with no HISTORY returns SUCCESS');
ok(! defined($myrep->{$HISTORY}), 'Still no HISTORY after calling event without initialisation');

# invalid HISTORY, but ok for this test
ok($myrep->set_report_history('invalidhistory'), 'set_report_history returns success');
is($myrep->{$HISTORY}, 'invalidhistory', 'set_report_history set HISTORY attribute');

ok($myrep->init_history(), 'init_history (w/o keepinstances) returns SUCCESS');
is_deeply($myrep->{$HISTORY}->{$EVENTS}, [], 'init_history created empty events');
ok(! exists($myrep->{$HISTORY}->{$INSTANCES}), 'No INSTANCES defined (w/o keepinstances)');
ok($myrep->event($obj), 'event with HISTORY w/o INSTANCES returns SUCCESS');

is(scalar @{$myrep->{$HISTORY}->{$EVENTS}}, 1, '1 event tracked');
ok(! exists($myrep->{$HISTORY}->{$INSTANCES}), 'No INSTANCES defined (w/o keepinstances) after event tracked');
is($myrep->{$HISTORY}->{$EVENTS}->[0]->{$WHOAMI}, 'myreporter',
   'WHOAMI metadata added to event tracked');

ok($myrep->init_history(1), '(re)init_history (with keepinstances) returns SUCCESS');
is_deeply($myrep->{$HISTORY}->{$EVENTS}, [], '(re)init_history created empty events');
is_deeply($myrep->{$HISTORY}->{$INSTANCES}, {}, 'empty INSTANCES defined (with keepinstances)');
ok($myrep->event($obj), 'event with HISTORY with INSTANCES returns SUCCESS');

is(scalar @{$myrep->{$HISTORY}->{$EVENTS}}, 1, '1 event tracked');
is_deeply($myrep->{$HISTORY}->{$INSTANCES},
          {'object_ok '.refaddr($obj) => $obj},
          'INSTANCES added (with keepinstances) after event tracked');
is($myrep->{$HISTORY}->{$EVENTS}->[0]->{$WHOAMI}, 'myreporter',
   'WHOAMI metadata added to event tracked');

=pod

=item verbose

=cut

$myrep->init_reporter();
is($CAF::Reporter::_REP_SETUP->{$VERBOSE}, 0, "Verbose disabled");
$reported = undef;
$syslogged = undef;
is($myrep->verbose('hello', 'verbose', 'disabled'), SUCCESS, 'verbose returns success with verbose disabled');
ok(! defined($reported), 'verbose does not report with verbose disabled');
ok(! defined($syslogged), 'verbose does not syslog with verbose disabled');


$myrep->config_reporter(debuglvl => 0, quiet => 0, verbose => 1);
is($CAF::Reporter::_REP_SETUP->{$VERBOSE}, 1, "Verbose enabled");
$reported = undef;
$syslogged = undef;
is($myrep->verbose('hello', 'verbose', 'enabled'), SUCCESS, 'verbose returns success with verbose enabled');
is_deeply($reported, ['[VERB] ', 'hello', 'verbose', 'enabled'],
          'verbose calls report with prefix and args with verbose enabled');
is_deeply($syslogged, ['notice', 'hello', 'verbose', 'enabled'],
          'verbose calls syslogs with notice priority and args with verbose verbose enabled');

$myrep->config_reporter(debuglvl => 0, quiet => 0, verbose => 0, facility => 'whatever', verbose_logfile => 1);
is($CAF::Reporter::_REP_SETUP->{$VERBOSE}, 0, "Verbose disabled (verbose_logfile)");
is($CAF::Reporter::_REP_SETUP->{$VERBOSE_LOGFILE}, 1, "Verbose logfile enabled");
$reported = undef;
$syslogged = undef;
$logged = undef;
is($myrep->verbose('hello', 'verbose_logfile', 'enabled'), SUCCESS, 'verbose returns success with verbose_logfile enabled');
ok(! defined($reported), 'report not called with only verbose_logfile');
ok(! defined($syslogged), 'syslog not called with only verbose_logfile');
is_deeply($logged, ['[VERB] ', 'hello', 'verbose_logfile', 'enabled'], "verbose calls log with only verbose_logfile");

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
is($CAF::Reporter::_REP_SETUP->{$DEBUGLV}, 0, "debuglv 0 set");
$reported = undef;
$syslogged = undef;
is($myrep->debug(1, 'hello', 'debug', 'lv0'), SUCCESS, 'debug1 returns success with debuglv0');
ok(! defined($reported), 'debug1 does not report with debuglv0');
ok(! defined($syslogged), 'debug1 does not syslog with debuglv0');

# equal level
$myrep->config_reporter(debuglvl => 1);
is($CAF::Reporter::_REP_SETUP->{$DEBUGLV}, 1, "debuglv 1 set");
is($myrep->debug(1, 'hello', 'debug', 'lv1'), SUCCESS, 'debug1 returns success with debuglv1');
is_deeply($reported, ['[DEBUG] ', 'hello', 'debug', 'lv1'],
          'debug calls report with prefix and args with lvl 1 equal debuglv 1');
is_deeply($syslogged, ['debug', 'hello', 'debug', 'lv1'],
          'debug calls syslogs with debug priority and args with lvl 1 equal debuglv 1');

# global lv > level
$myrep->config_reporter(debuglvl => 2);
is($CAF::Reporter::_REP_SETUP->{$DEBUGLV}, 2, "debuglv 2 set");
is($myrep->debug(1, 'hello', 'debug', 'lv2'), SUCCESS, 'debug1 returns success with debuglv2');
is_deeply($reported, ['[DEBUG] ', 'hello', 'debug', 'lv2'],
          'debug calls report with prefix and args with lvl 1 lower than debuglv 2');
is_deeply($syslogged, ['debug', 'hello', 'debug', 'lv2'],
          'debug calls syslogs with debug priority and args with lvl 1 lower than debuglv 2');

=pod

=item Reporter uses "global" _REP_SETUP

=cut

$myrep->init_reporter();
$reported = undef;

my $myrep2 = myreporter->new();
isa_ok($myrep2, 'myreporter', 'myrep2 is a myreporter instance');

$myrep->config_reporter(debuglvl => 2);

is($myrep2->debug(1, 'hello', 'myrep2', 'debug', 'lv2'),
   SUCCESS, 'myrep2 debug1 returns success with debuglv2');
is_deeply($reported, ['[DEBUG] ', 'hello', 'myrep2', 'debug', 'lv2'],
          'myrep2 debug call reports, following debuglevel set with other myrep instance');

=pod

=item ReporterMany uses "global" _REP_SETUP on init, but any changes are per instance.

=cut

my ($mcurrent1, $mcurrent2);

# no re-init
my $mymany1 = myreportermany->new();
isa_ok($mymany1, 'myreportermany', 'mymany1 is a myreportermany instance');
$reported = undef;
is($mymany1->debug(1, 'hello', 'mymany1', 'debug', 'lv2'),
   SUCCESS, 'mymany1 debug1 returns success with debuglv2');
is_deeply($reported, ['[DEBUG] ', 'hello', 'mymany1', 'debug', 'lv2'],
          'mymany1 debug call reports, following debuglevel set with other myrep instance via global _REP_SETUP on init');

foreach my $k (keys %$CAF::Reporter::_REP_SETUP) {
    ok(exists($mymany1->{$k}), "mymany1 reporter config $k set");
    $mcurrent1->{$k} = $mymany1->{$k};
}

is_deeply($mcurrent1, $CAF::Reporter::_REP_SETUP,
          "mymany1 init reporter config from global _REP_SETUP");

# disable debug level on mymany1
is($mymany1->{DEBUGLV}, 2, "mymany1 debuglv set to 2");
$mymany1->config_reporter(debuglvl => 0);
$reported = undef;
is($mymany1->debug(1, 'hello', 'mymany1', 'debug', 'lv0'),
   SUCCESS, 'mymany1 debug1 returns success with debuglv0');
ok(! defined($reported),
   'mymany1 debug call does not reports, following debuglevel set with own myrepmany instance');
is($mymany1->{DEBUGLV}, 0, "mymany1 debuglv set to 0");

# report with reporter
is($myrep->debug(1, 'hello', 'debug', 'postmany', 'lv2'), SUCCESS,
   'myrep debug1 returns success with debuglv2');
is_deeply($reported, ['[DEBUG] ', 'hello', 'debug', 'postmany', 'lv2'],
          'myrep debug call still reports after mymany1 debug level changed');

# new myreportermany
my $mymany2 = myreportermany->new();
isa_ok($mymany2, 'myreportermany', 'mymany2 is a myreportermany instance');
$reported = undef;
is($mymany2->debug(1, 'hello', 'mymany2', 'debug', 'lv2'),
   SUCCESS, 'mymany2 debug1 returns success with debuglv2');
is_deeply($reported, ['[DEBUG] ', 'hello', 'mymany2', 'debug', 'lv2'],
          'mymany2 debug call reports, following debuglevel set with other myrep instance via global _REP_SETUP on init (and not other reportermany instance)');

foreach my $k (keys %$CAF::Reporter::_REP_SETUP) {
    ok(exists($mymany2->{$k}), "mymany2 reporter config $k set");
    $mcurrent2->{$k} = $mymany2->{$k};
}

is_deeply($mcurrent2, $CAF::Reporter::_REP_SETUP,
          "mymany2 init reporter config from global _REP_SETUP");


$mymany2->config_reporter(debuglvl => 5);
is($mymany2->{DEBUGLV}, 5, "mymany2 debuglv set to 5");
is($mymany1->{DEBUGLV}, 0, "mymany1 debuglv unmodified at 0");

=item legacy methods setup_reporter / set_report_logfile

=cut

my $opts;
$mock->mock('config_reporter', sub {shift; $opts = {@_}; return 123});

$opts = undef;
is($myrep->setup_reporter(qw(a b c d e)), 123, "setup_reporter returns config_reporter value");
is_deeply($opts, {
    debuglvl => 'a',
    quiet => 'b',
    verbose => 'c',
    facility => 'd',
    verbose_logfile => 'e',
}, "setup_reporter calls config_reporter options");

$opts = undef;
is($myrep->set_report_logfile(123), 123, "set_report_logfile returns config_reporter value");
is_deeply($opts, {logfile => 123},
          "set_report_logfile calls config_reporter with logfile value");

$opts = undef;
$myrep->set_report_logfile();
is_deeply($opts, {logfile => 0},
          "set_report_logfile(undef) is equal to config_reporter with false logfile value");


=pod

=back

=cut

done_testing();
