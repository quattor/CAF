# -*- mode: cperl -*-
# ${license-info}
# ${author-info}
# ${build-info}

use strict;
use warnings;
use FindBin qw($Bin);
use lib "$Bin/modules";
use CAF::RuleBasedEditor qw(:rule_constants);
use Readonly;
use CAF::Object;
use Test::More tests => 21;
use Test::NoWarnings;
use Test::Quattor;
use Test::Quattor::Object;
use Carp qw(confess);

Test::NoWarnings::clear_warnings();


=pod

=head1 SYNOPSIS

Basic test for rule-based editor (line pattern build)

=cut

Readonly my $FILENAME => '/my/file';

my $obj = Test::Quattor::Object->new();

$SIG{__DIE__} = \&confess;

my $escaped_pattern;

my $fh = CAF::RuleBasedEditor->open($FILENAME, log => $obj);
ok(defined($fh), $FILENAME." was opened");

# First test the function used to escape special characters in patterns
Readonly my $PATTERN_NO_SPECIAL_CHARS => 'abcdef12389';
Readonly my $PATTERN_WITH_SPECIAL_CHARS => '-+?.*  []()^	${}';
Readonly my $EXPECTED_WITH_SPECIAL_CHARS => '\-\+\?\.\*\s+\[\]\(\)\^\s+\$\{\}';
$escaped_pattern = $fh->_escape_regexp_string($PATTERN_NO_SPECIAL_CHARS);
is($escaped_pattern, $PATTERN_NO_SPECIAL_CHARS, "Pattern without special characters ok");
$escaped_pattern = $fh->_escape_regexp_string($PATTERN_WITH_SPECIAL_CHARS);
is($escaped_pattern, $EXPECTED_WITH_SPECIAL_CHARS, "Pattern with special characters ok");

# Build a line pattern without a parameter value
Readonly my $KEYWORD => 'DPNS_HOST';
Readonly my $LINE_PATTERN_ENV_VAR => '#?\s*export\s+DPNS_HOST=';
Readonly my $LINE_PATTERN_KW_VALUE => '#?\s*DPNS_HOST';
$escaped_pattern = $fh->_buildLinePattern($KEYWORD,
                                          LINE_FORMAT_ENV_VAR,
                                          0);
is($escaped_pattern, $LINE_PATTERN_ENV_VAR, "Environment variable pattern ok");
$escaped_pattern = $fh->_buildLinePattern($KEYWORD,
                                          LINE_FORMAT_KW_VAL,
                                          0);
is($escaped_pattern, $LINE_PATTERN_KW_VALUE, "Key/value pattern ok");

# Build a line pattern with a parameter value
Readonly my $VALUE_1 => 'dpns.example.com';
Readonly my $EXPECTED_PATTERN_1 => '#?\s*export\s+DPNS_HOST=dpns\.example\.com';
Readonly my $VALUE_2 => 0;
Readonly my $EXPECTED_PATTERN_2 => '#?\s*export\s+DPNS_HOST=0';
Readonly my $VALUE_3 => '^dp$n-s.*ex] a+m(p{le[.c)o}+m?';
Readonly my $EXPECTED_PATTERN_3 => '#?\s*export\s+DPNS_HOST=\^dp\$n\-s\.\*ex\]\s+a\+m\(p\{le\[\.c\)o\}\+m\?';
# Test \ escaping separately as it also needs the expected value also needs to be escaped for the test
# to be successful!
Readonly my $VALUE_4 => 'a\b';
Readonly my $EXPECTED_PATTERN_4 => '#?\s*export\s+DPNS_HOST=a\\\\b';
Readonly my $KEYWORD_SPECIAL => 'DPM$H{OS}T';
Readonly my $KEYWORD_SPECIAL_VALUE => 'value';
Readonly my $EXPECTED_PATTERN_5 => '#?\s*export\s+DPM\$H\{OS\}T=value';
Readonly my $EXPECTED_PATTERN_SH_VAR => '#?\s*DPNS_HOST=dpns\.example\.com';
Readonly my $EXPECTED_PATTERN_KV => '#?\s*DPNS_HOST\s*(?:\s|=|:)\s*dpns\.example\.com';
Readonly my $EXPECTED_PATTERN_KV_COLON => '#?\s*DPNS_HOST\s*(?:\s|=|:)\s*dpns\.example\.com';
Readonly my $EXPECTED_PATTERN_KV_EQUAL => '#?\s*DPNS_HOST\s*(?:\s|=|:)\s*dpns\.example\.com';
Readonly my $EXPECTED_PATTERN_SET => '#?\s*set\s+DPNS_HOST\s*(?:\s|=|:)\s*dpns\.example\.com';
Readonly my $EXPECTED_PATTERN_SET_COLON => '#?\s*set\s+DPNS_HOST\s*(?:\s|=|:)\s*dpns\.example\.com';
Readonly my $EXPECTED_PATTERN_SET_EQUAL => '#?\s*set\s+DPNS_HOST\s*(?:\s|=|:)\s*dpns\.example\.com';
Readonly my $EXPECTED_PATTERN_SETENV => '#?\s*setenv\s+DPNS_HOST\s*(?:\s|=|:)\s*dpns\.example\.com';
Readonly my $EXPECTED_PATTERN_SETENV_COLON => '#?\s*setenv\s+DPNS_HOST\s*(?:\s|=|:)\s*dpns\.example\.com';
Readonly my $EXPECTED_PATTERN_SETENV_EQUAL => '#?\s*setenv\s+DPNS_HOST\s*(?:\s|=|:)\s*dpns\.example\.com';
$escaped_pattern = $fh->_buildLinePattern($KEYWORD,
                                          LINE_FORMAT_ENV_VAR,
                                          0,
                                          $VALUE_1);
is($escaped_pattern, $EXPECTED_PATTERN_1, "Environment variable with value (host name): pattern ok");
$escaped_pattern = $fh->_buildLinePattern($KEYWORD,
                                          LINE_FORMAT_ENV_VAR,
                                          0,
                                          $VALUE_2);
is($escaped_pattern, $EXPECTED_PATTERN_2, "Environment variable with value (0): pattern ok");
$escaped_pattern = $fh->_buildLinePattern($KEYWORD,
                                          LINE_FORMAT_ENV_VAR,
                                          0,
                                          $VALUE_3);
is($escaped_pattern, $EXPECTED_PATTERN_3, "Environment variable with value (special characters): pattern ok");
$escaped_pattern = $fh->_buildLinePattern($KEYWORD,
                                          LINE_FORMAT_ENV_VAR,
                                          0,
                                          $VALUE_4);
is($escaped_pattern, $EXPECTED_PATTERN_4, "Environment variable with value (backslash): pattern ok");
$escaped_pattern = $fh->_buildLinePattern($KEYWORD_SPECIAL,
                                          LINE_FORMAT_ENV_VAR,
                                          0,
                                          $KEYWORD_SPECIAL_VALUE);
is($escaped_pattern, $EXPECTED_PATTERN_5, "Environment variable with special characters in keyword: pattern ok");
$escaped_pattern = $fh->_buildLinePattern($KEYWORD,
                                          LINE_FORMAT_SH_VAR,
                                          0,
                                          $VALUE_1);
is($escaped_pattern, $EXPECTED_PATTERN_SH_VAR, "SH shell variable with value (host name): pattern ok");
$escaped_pattern = $fh->_buildLinePattern($KEYWORD,
                                          LINE_FORMAT_KW_VAL,
                                          0,
                                          $VALUE_1);
is($escaped_pattern, $EXPECTED_PATTERN_KV, "'keyword value': pattern ok");
$escaped_pattern = $fh->_buildLinePattern($KEYWORD,
                                          LINE_FORMAT_KW_VAL,
                                          LINE_OPT_SEP_COLON,
                                          $VALUE_1);
is($escaped_pattern, $EXPECTED_PATTERN_KV_COLON, "'keyword:value': pattern ok");
$escaped_pattern = $fh->_buildLinePattern($KEYWORD,
                                          LINE_FORMAT_KW_VAL,
                                          LINE_OPT_SEP_EQUAL,
                                          $VALUE_1);
is($escaped_pattern, $EXPECTED_PATTERN_KV_EQUAL, "'keyword=value': pattern ok");
$escaped_pattern = $fh->_buildLinePattern($KEYWORD,
                                          LINE_FORMAT_KW_VAL_SET,
                                          0,
                                          $VALUE_1);
is($escaped_pattern, $EXPECTED_PATTERN_SET, "'set keyword value': pattern ok");
$escaped_pattern = $fh->_buildLinePattern($KEYWORD,
                                          LINE_FORMAT_KW_VAL_SET,
                                          LINE_OPT_SEP_COLON,
                                          $VALUE_1);
is($escaped_pattern, $EXPECTED_PATTERN_SET_COLON, "'set keyword:value': pattern ok");
$escaped_pattern = $fh->_buildLinePattern($KEYWORD,
                                          LINE_FORMAT_KW_VAL_SET,
                                          LINE_OPT_SEP_EQUAL,
                                          $VALUE_1);
is($escaped_pattern, $EXPECTED_PATTERN_SET_EQUAL, "'set keyword=value': pattern ok");
$escaped_pattern = $fh->_buildLinePattern($KEYWORD,
                                          LINE_FORMAT_KW_VAL_SETENV,
                                          0,
                                          $VALUE_1);
is($escaped_pattern, $EXPECTED_PATTERN_SETENV, "'setenv keyword value': pattern ok");
$escaped_pattern = $fh->_buildLinePattern($KEYWORD,
                                          LINE_FORMAT_KW_VAL_SETENV,
                                          LINE_OPT_SEP_COLON,
                                          $VALUE_1);
is($escaped_pattern, $EXPECTED_PATTERN_SETENV_COLON, "'setenv:keyword value': pattern ok");
$escaped_pattern = $fh->_buildLinePattern($KEYWORD,
                                          LINE_FORMAT_KW_VAL_SETENV,
                                          LINE_OPT_SEP_EQUAL,
                                          $VALUE_1);
is($escaped_pattern, $EXPECTED_PATTERN_SETENV_EQUAL, "'setenv=keyword value': pattern ok");

$fh->close();

# Test::NoWarnings::had_no_warnings();

