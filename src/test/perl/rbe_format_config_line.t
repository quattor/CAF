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
use Test::More tests => 4;
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

my $formatted_value;
my $rbe_fh = CAF::RuleBasedEditor->open($FILENAME, log => $obj);
ok(defined($rbe_fh), $FILENAME." was opened");


# Various combination of keyword and values
Readonly my $KEYWORD_SIMPLE => 'A_KEYWORD';
Readonly my $KEYWORD_SPACE => 'A KEYWORD';

Readonly my $VALUE_STR_SIMPLE => 'this is a value';


# Expected line contents
Readonly my $EXPECTED_KW_VAL_SIMPLE => 'A_KEYWORD this is a value';
Readonly my $EXPECTED_KW_VAL_SPACE => 'A KEYWORD this is a value';


# LINE_FORMAT_KW_VAL
$line = $rbe_fh->_formatConfigLine($KEYWORD_SIMPLE, $VALUE_STR_SIMPLE, LINE_FORMAT_KW_VAL, 0);
is($line, $EXPECTED_KW_VAL_SIMPLE, 'simple keyword + value properly formatted');
$line = $rbe_fh->_formatConfigLine($KEYWORD_SPACE, $VALUE_STR_SIMPLE, LINE_FORMAT_KW_VAL, 0);
is($line, $EXPECTED_KW_VAL_SPACE, 'keyword with space + value properly formatted');

