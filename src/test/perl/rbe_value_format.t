# -*- mode: cperl -*-
# ${license-info}
# ${author-info}
# ${build-info}

use strict;
use warnings;
use FindBin qw($Bin);
use lib "$Bin/modules";
use testapp;
use CAF::FileEditor;
use CAF::RuleBasedEditor qw(:rule_constants);
use Readonly;
use CAF::Object;
use Test::More tests => 20;
use Test::NoWarnings;
use Test::Quattor;
use Carp qw(confess);

Test::NoWarnings::clear_warnings();


=pod

=head1 SYNOPSIS

Basic test for rule-based editor (value formatting)

=cut

Readonly my $FILENAME => '/my/file';

our %opts = ();
our $path;
my ($log, $str);
my $this_app = testapp->new ($0, qw (--verbose));

$SIG{__DIE__} = \&confess;

*testapp::error = sub {
    my $self = shift;
    $self->{ERROR} = @_;
};


open ($log, ">", \$str);
$this_app->set_report_logfile ($log);

my $formatted_value;
my $rbe_fh = CAF::FileEditor->open($FILENAME, log => $this_app);
ok(defined($rbe_fh), $FILENAME." was opened");

# LINE_VALUE_BOOLEAN
Readonly my $FALSE => 'no';
Readonly my $TRUE => 'yes';
Readonly my $TRUE_QUOTED => '"yes"';
$formatted_value = $rbe_fh->_formatAttributeValue(0,
                                               LINE_FORMAT_XRDCFG,
                                               LINE_VALUE_BOOLEAN,
                                               0,
                                              );
is($formatted_value, $FALSE, "Boolean (false) correctly formatted");
$formatted_value = $rbe_fh->_formatAttributeValue(1,
                                               LINE_FORMAT_XRDCFG,
                                               LINE_VALUE_BOOLEAN,
                                               0,
                                              );
is($formatted_value, $TRUE, "Boolean (true) correctly formatted");
$formatted_value = $rbe_fh->_formatAttributeValue(1,
                                               LINE_FORMAT_PARAM,
                                               LINE_VALUE_BOOLEAN,
                                               0,
                                              );
is($formatted_value, $TRUE_QUOTED, "Boolean (true, quoted) correctly formatted");


# LINE_VALUE_AS_IS
Readonly my $AS_IS_VALUE => 'This is a Test';
Readonly my $AS_IS_VALUE_DOUBLE_QUOTED => '"This is a Test"';
Readonly my $AS_IS_VALUE_SINGLE_QUOTED => "'This is a Test'";
Readonly my $EMPTY_VALUE => '';
Readonly my $EMPTY_VALUE_QUOTED => '""';
$formatted_value = $rbe_fh->_formatAttributeValue($AS_IS_VALUE,
                                               LINE_FORMAT_XRDCFG,
                                               LINE_VALUE_AS_IS,
                                               0,
                                              );
is($formatted_value, $AS_IS_VALUE, "Literal value correctly formatted");
$formatted_value = $rbe_fh->_formatAttributeValue($AS_IS_VALUE,
                                               LINE_FORMAT_ENVVAR,
                                               LINE_VALUE_AS_IS,
                                               0,
                                              );
is($formatted_value, $AS_IS_VALUE_DOUBLE_QUOTED, "Literal value (quoted) correctly formatted");
$formatted_value = $rbe_fh->_formatAttributeValue($AS_IS_VALUE_DOUBLE_QUOTED,
                                               LINE_FORMAT_XRDCFG,
                                               LINE_VALUE_AS_IS,
                                               0,
                                              );
is($formatted_value, $AS_IS_VALUE_DOUBLE_QUOTED, "Quoted literal value correctly formatted");
$formatted_value = $rbe_fh->_formatAttributeValue($AS_IS_VALUE_DOUBLE_QUOTED,
                                               LINE_FORMAT_ENVVAR,
                                               LINE_VALUE_AS_IS,
                                               0,
                                              );
is($formatted_value, $AS_IS_VALUE_DOUBLE_QUOTED, "Already quoted literal value correctly formatted");
$formatted_value = $rbe_fh->_formatAttributeValue($AS_IS_VALUE_SINGLE_QUOTED,
                                               LINE_FORMAT_ENVVAR,
                                               LINE_VALUE_AS_IS,
                                               0,
                                              );
is($formatted_value, $AS_IS_VALUE_SINGLE_QUOTED, "Already single quoted literal value correctly formatted");
$formatted_value = $rbe_fh->_formatAttributeValue($EMPTY_VALUE,
                                               LINE_FORMAT_XRDCFG,
                                               LINE_VALUE_AS_IS,
                                               0,
                                              );
is($formatted_value, $EMPTY_VALUE, "Empty value correctly formatted");
$formatted_value = $rbe_fh->_formatAttributeValue($EMPTY_VALUE,
                                               LINE_FORMAT_PARAM,
                                               LINE_VALUE_AS_IS,
                                               0,
                                              );
is($formatted_value, $EMPTY_VALUE_QUOTED, "Empty value (quoted) correctly formatted");


# LINE_VALUE_INSTANCE_PARAMS
# configFile intentionally misspelled confFile for testing
Readonly my %INSTANCE_PARAMS => (logFile => '/test/instance.log',
                                 confFile => '/test/instance.conf',
                                 logKeep => 60,
                                 unused => 'dummy',
                                );
Readonly my $FORMATTED_INSTANCE_PARAMS => ' -l /test/instance.log -k 60';
Readonly my $FORMATTED_INSTANCE_PARAMS_QUOTED => '" -l /test/instance.log -k 60"';
$formatted_value = $rbe_fh->_formatAttributeValue(\%INSTANCE_PARAMS,
                                               LINE_FORMAT_XRDCFG,
                                               LINE_VALUE_INSTANCE_PARAMS,
                                               0,
                                              );
is($formatted_value, $FORMATTED_INSTANCE_PARAMS, "Instance params correctly formatted");
$formatted_value = $rbe_fh->_formatAttributeValue(\%INSTANCE_PARAMS,
                                               LINE_FORMAT_PARAM,
                                               LINE_VALUE_INSTANCE_PARAMS,
                                               0,
                                              );
is($formatted_value, $FORMATTED_INSTANCE_PARAMS_QUOTED, "Instance params (quoted) correctly formatted");


# LINE_VALUE_ARRAY
Readonly my @TEST_ARRAY => ('confFile', 'logFile', 'unused', 'logKeep', 'logFile');
Readonly my $FORMATTED_ARRAY => 'confFile logFile unused logKeep logFile';
Readonly my $FORMATTED_ARRAY_SORTED => 'confFile logFile logFile logKeep unused';
Readonly my $FORMATTED_ARRAY_UNIQUE => 'confFile logFile logKeep unused';
my $rbe_fh = CAF::FileEditor->open($FILENAME, log => $this_app);
ok(defined($rbe_fh), $FILENAME." was opened");
$formatted_value = $rbe_fh->_formatAttributeValue(\@TEST_ARRAY,
                                               LINE_FORMAT_XRDCFG,
                                               LINE_VALUE_ARRAY,
                                               0,
                                              );
is($formatted_value, $FORMATTED_ARRAY, "Array values correctly formatted");
$formatted_value = $rbe_fh->_formatAttributeValue(\@TEST_ARRAY,
                                               LINE_FORMAT_XRDCFG,
                                               LINE_VALUE_ARRAY,
                                               LINE_VALUE_OPT_SORTED,
                                              );
is($formatted_value, $FORMATTED_ARRAY_SORTED, "Array values (sorted) correctly formatted");
$formatted_value = $rbe_fh->_formatAttributeValue(\@TEST_ARRAY,
                                               LINE_FORMAT_XRDCFG,
                                               LINE_VALUE_ARRAY,
                                               LINE_VALUE_OPT_UNIQUE,
                                              );
is($formatted_value, $FORMATTED_ARRAY_UNIQUE, "Array values (unique) correctly formatted");


# LINE_VALUE_HASH_KEYS
$formatted_value = $rbe_fh->_formatAttributeValue(\%INSTANCE_PARAMS,
                                               LINE_FORMAT_XRDCFG,
                                               LINE_VALUE_HASH_KEYS,
                                               0,
                                              );
is($formatted_value, $FORMATTED_ARRAY_UNIQUE, "Hash keys correctly formatted");


Test::NoWarnings::had_no_warnings();
