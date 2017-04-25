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
use Test::More tests => 29;
use Test::NoWarnings;
use Test::Quattor;
use Test::Quattor::Object;
use Carp qw(confess);

Test::NoWarnings::clear_warnings();


=pod

=head1 SYNOPSIS

Basic test for rule-based editor (_formatConfigLine() method)

=cut

Readonly my $FILENAME => '/my/file';

my $obj = Test::Quattor::Object->new();

$SIG{__DIE__} = \&confess;

my $line;

my $rbe_fh = CAF::RuleBasedEditor->open($FILENAME, log => $obj);
ok(defined($rbe_fh), $FILENAME." was opened");


# Various combination of keyword and values
Readonly my $KEYWORD_SIMPLE => 'A_KEYWORD';
Readonly my $KEYWORD_SPACE => 'A KEYWORD';

Readonly my $VALUE_STR => 'this is a value';


# Expected line contents
Readonly my $EXPECTED_KW_VAL_SIMPLE => 'A_KEYWORD this is a value';
Readonly my $EXPECTED_KW_VAL_SPACE => 'A KEYWORD this is a value';
Readonly my $EXPECTED_KW_VAL_EMPTY => 'A_KEYWORD';
Readonly my $EXPECTED_KW_VAL_EMPTY_SPACE => 'A KEYWORD';
Readonly my $EXPECTED_KW_VAL_COLON => 'A_KEYWORD:this is a value';
Readonly my $EXPECTED_KW_VAL_COLON_SPACE => 'A_KEYWORD : this is a value';
Readonly my $EXPECTED_KW_VAL_EQUAL => 'A_KEYWORD=this is a value';
Readonly my $EXPECTED_KW_VAL_EQUAL_SPACE => 'A_KEYWORD = this is a value';

Readonly my $EXPECTED_SH_VAR_SIMPLE => 'A_KEYWORD=this is a value';
Readonly my $EXPECTED_SH_VAR_EMPTY => 'A_KEYWORD=';


# LINE_FORMAT_KW_VAL
$line = $rbe_fh->_formatConfigLine($KEYWORD_SIMPLE, $VALUE_STR, LINE_FORMAT_KW_VAL, 0);
is($line, $EXPECTED_KW_VAL_SIMPLE, 'simple keyword + value properly formatted');
$line = $rbe_fh->_formatConfigLine($KEYWORD_SPACE, $VALUE_STR, LINE_FORMAT_KW_VAL, 0);
is($line, $EXPECTED_KW_VAL_SPACE, 'keyword with space + value properly formatted');
$line = $rbe_fh->_formatConfigLine($KEYWORD_SIMPLE, '', LINE_FORMAT_KW_VAL, 0);
is($line, $EXPECTED_KW_VAL_EMPTY, 'simple keyword + empty value properly formatted');
$line = $rbe_fh->_formatConfigLine($KEYWORD_SPACE, '', LINE_FORMAT_KW_VAL, 0);
is($line, $EXPECTED_KW_VAL_EMPTY_SPACE, 'keyword with space + empty value properly formatted');
$line = $rbe_fh->_formatConfigLine($KEYWORD_SIMPLE, $VALUE_STR, LINE_FORMAT_KW_VAL, LINE_OPT_SEP_COLON);
is($line, $EXPECTED_KW_VAL_COLON, '"keyword:value" properly formatted');
$line = $rbe_fh->_formatConfigLine($KEYWORD_SIMPLE, $VALUE_STR, LINE_FORMAT_KW_VAL, LINE_OPT_SEP_COLON | LINE_OPT_SEP_SPACE_AROUND);
is($line, $EXPECTED_KW_VAL_COLON_SPACE, '"keyword : value" properly formatted');
$line = $rbe_fh->_formatConfigLine($KEYWORD_SIMPLE, $VALUE_STR, LINE_FORMAT_KW_VAL, LINE_OPT_SEP_EQUAL);
is($line, $EXPECTED_KW_VAL_EQUAL, '"keyword=value" properly formatted');
$line = $rbe_fh->_formatConfigLine($KEYWORD_SIMPLE, $VALUE_STR, LINE_FORMAT_KW_VAL, LINE_OPT_SEP_EQUAL | LINE_OPT_SEP_SPACE_AROUND);
is($line, $EXPECTED_KW_VAL_EQUAL_SPACE, '"keyword = value" properly formatted');

# LINE_FORMAT_KW_VAL_SET
$line = $rbe_fh->_formatConfigLine($KEYWORD_SIMPLE, $VALUE_STR, LINE_FORMAT_KW_VAL_SET, 0);
is($line, 'set '.$EXPECTED_KW_VAL_SIMPLE, 'simple keyword + value properly formatted');
$line = $rbe_fh->_formatConfigLine($KEYWORD_SPACE, $VALUE_STR, LINE_FORMAT_KW_VAL_SET, 0);
is($line, 'set '.$EXPECTED_KW_VAL_SPACE, 'keyword with space + value properly formatted');
$line = $rbe_fh->_formatConfigLine($KEYWORD_SIMPLE, $VALUE_STR, LINE_FORMAT_KW_VAL_SET, LINE_OPT_SEP_COLON);
is($line, 'set '.$EXPECTED_KW_VAL_COLON, '"keyword:value" properly formatted');
$line = $rbe_fh->_formatConfigLine($KEYWORD_SIMPLE, $VALUE_STR, LINE_FORMAT_KW_VAL_SET, LINE_OPT_SEP_COLON | LINE_OPT_SEP_SPACE_AROUND);
is($line, 'set '.$EXPECTED_KW_VAL_COLON_SPACE, '"keyword : value" properly formatted');
$line = $rbe_fh->_formatConfigLine($KEYWORD_SIMPLE, $VALUE_STR, LINE_FORMAT_KW_VAL_SET, LINE_OPT_SEP_EQUAL);
is($line, 'set '.$EXPECTED_KW_VAL_EQUAL, '"keyword=value" properly formatted');
$line = $rbe_fh->_formatConfigLine($KEYWORD_SIMPLE, $VALUE_STR, LINE_FORMAT_KW_VAL_SET, LINE_OPT_SEP_EQUAL | LINE_OPT_SEP_SPACE_AROUND);
is($line, 'set '.$EXPECTED_KW_VAL_EQUAL_SPACE, '"keyword = value" properly formatted');

# LINE_FORMAT_KW_VAL_SETENV
$line = $rbe_fh->_formatConfigLine($KEYWORD_SIMPLE, $VALUE_STR, LINE_FORMAT_KW_VAL_SETENV, 0);
is($line, 'setenv '.$EXPECTED_KW_VAL_SIMPLE, 'simple keyword + value properly formatted');
$line = $rbe_fh->_formatConfigLine($KEYWORD_SPACE, $VALUE_STR, LINE_FORMAT_KW_VAL_SETENV, 0);
is($line, 'setenv '.$EXPECTED_KW_VAL_SPACE, 'keyword with space + value properly formatted');
$line = $rbe_fh->_formatConfigLine($KEYWORD_SIMPLE, $VALUE_STR, LINE_FORMAT_KW_VAL_SETENV, LINE_OPT_SEP_COLON);
is($line, 'setenv '.$EXPECTED_KW_VAL_COLON, '"keyword:value" properly formatted');
$line = $rbe_fh->_formatConfigLine($KEYWORD_SIMPLE, $VALUE_STR, LINE_FORMAT_KW_VAL_SETENV, LINE_OPT_SEP_COLON | LINE_OPT_SEP_SPACE_AROUND);
is($line, 'setenv '.$EXPECTED_KW_VAL_COLON_SPACE, '"keyword : value" properly formatted');
$line = $rbe_fh->_formatConfigLine($KEYWORD_SIMPLE, $VALUE_STR, LINE_FORMAT_KW_VAL_SETENV, LINE_OPT_SEP_EQUAL);
is($line, 'setenv '.$EXPECTED_KW_VAL_EQUAL, '"keyword=value" properly formatted');
$line = $rbe_fh->_formatConfigLine($KEYWORD_SIMPLE, $VALUE_STR, LINE_FORMAT_KW_VAL_SETENV, LINE_OPT_SEP_EQUAL | LINE_OPT_SEP_SPACE_AROUND);
is($line, 'setenv '.$EXPECTED_KW_VAL_EQUAL_SPACE, '"keyword = value" properly formatted');

# LINE_FORMAT_SH_VAR
$line = $rbe_fh->_formatConfigLine($KEYWORD_SIMPLE, $VALUE_STR, LINE_FORMAT_SH_VAR, 0);
is($line, $EXPECTED_SH_VAR_SIMPLE, 'SH variable properly formatted');
$line = $rbe_fh->_formatConfigLine($KEYWORD_SIMPLE, $VALUE_STR, LINE_FORMAT_SH_VAR, LINE_OPT_SEP_EQUAL | LINE_OPT_SEP_SPACE_AROUND);
is($line, $EXPECTED_SH_VAR_SIMPLE, 'SH variable: LINE_OPT_SEP ignored');
$line = $rbe_fh->_formatConfigLine($KEYWORD_SIMPLE, '', LINE_FORMAT_SH_VAR, 0);
is($line, $EXPECTED_SH_VAR_EMPTY, 'SH variable with empty value properly formatted');

# LINE_FORMAT_ENV_VAR
$line = $rbe_fh->_formatConfigLine($KEYWORD_SIMPLE, $VALUE_STR, LINE_FORMAT_ENV_VAR, 0);
is($line, 'export '.$EXPECTED_SH_VAR_SIMPLE, 'Environment variable properly formatted');
$line = $rbe_fh->_formatConfigLine($KEYWORD_SIMPLE, $VALUE_STR, LINE_FORMAT_ENV_VAR, LINE_OPT_SEP_COLON);
is($line, 'export '.$EXPECTED_SH_VAR_SIMPLE, 'Environment variable: LINE_OPT_SEP ignored');
$line = $rbe_fh->_formatConfigLine($KEYWORD_SIMPLE, $VALUE_STR, LINE_FORMAT_ENV_VAR, LINE_OPT_SEP_SPACE_AROUND);
is($line, 'export '.$EXPECTED_SH_VAR_SIMPLE, 'Environment variable: LINE_OPT_SEP ignored');
$line = $rbe_fh->_formatConfigLine($KEYWORD_SIMPLE, '', LINE_FORMAT_ENV_VAR, 0);
is($line, 'export '.$EXPECTED_SH_VAR_EMPTY, 'Environment variable with empty value properly formatted');

$rbe_fh->close();
