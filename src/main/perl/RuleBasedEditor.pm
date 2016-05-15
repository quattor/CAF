# ${license-info}
# ${developer-info}
# ${author-info}
# ${build-info}

=pod

=head1 DESCRIPTION

This module implements a rule-based editor that is used to modify the content
of an existing file. Each rule driving the editing process is applied to all
lines wose "keyword" is matching the one specified in the rule. The input for
updating the file is a hash typically built from the Quattor configuration when
the rule-based editor is called from a configuration module. Conditions can be defined
based on the contents of this configuration. Lines in the configuration file
that don't match any rule are kept unmodified.

This module is a subclass of the L<CAF::FileEditor>: it extends the base methods of
the L<CAF::FileEditor>. It has only one public method (it uses the L<CAF::FileEditor> constructor).
The methods provided in this module can be combined with L<CAF::FileEditor>
methods to edit a file.

Rules used to edit the file are defined in a hash: each entry (key/value pair) defines a rule.
Multiple rules can be applied to the same file: it is important that they are
orthogonal, else the result is unpredictable. The order used to apply rules is the alphabetical
order of keywords. Applying the rules to the same configuration always give the same result
but the changes are not necessarily idempotent (order in which successive edits occured
may matter, depending on the actual rules).

The hash entry key represents the line keyword in configuration file and
hash value is the parsing rule for the keyword value. Parsing rule format is :

      [condition->]option_name:option_set[,option_set,...];line_fmt[;value_fmt[:value_fmt_opt]]

If the line keyword (hash key) starts with a '-', the matching
configuration line will be removed/commented out (instead of added/updated) from the
configuration file if present. If it starts with a '?', the
matching line will be removed/commented out if the option is undefined.

=over

=item condition

An option or an option set/subset (see below) that must exist for the rule to be applied
or the keyword C<ALWAYS>.
Both C<option_set> and C<option_name:option_set> are accepted. option and option set
in the condition are normally different from the C<option_name> and C<option_set>
parameters in the rule as this is the default behaviour to apply the rule only if
they exist. One option set only is allowed and only its existence (not its value) is tested.

C<option_set> can be either an actual option set as defined below or a subset of an option set
(a subhash of the option set hash). To specify a subset, use C</> as a level separator, 
e.g. C<xroot/securityProtocol/gsi> (C<gsi> subet of C<securityProtocol> subset of C<xroot> option set).

It is possible to negate the condition (option or option_set must not exist)
by prepending it with '!'.

C<ALWAYS> is a special condition that means that rules must be applied whether
the C<option_name:option_set> exist in the configuration or not. When they don't exist
the result is to comment out the matching configuration lines.

=item option_name

The name of an option that will be retrieved from the configuration. An option is
a key in the option set hash.

=item option_set

The name of an option set where the option is located in (for example 'dpnsHost:dpm'
means C<dpnsHost> option of C<dpm> option set). An option set is a sub-hash in the configuration
hash. C<GLOBAL> is a special value for C<option_set> indicating that the option is a global option,
instead of belonging to a specific option set (global options are at the top level of the configuration
hash).

=item line_fmt

Defines the format used to represent the keyword/value pair. Several format are supported covering
the most usual ones (SH shell script, Apache, ...). For the exact list, see the definition of
LINE_FORMAT_xxx constants and the associated documentation below.

=item value_fmt

used to indicate how to interpret the configuration value. It is used mainly for
boolean values, list and hashes. See LINE_VALUE_xxx constants below for the possible values.

=item value_fmt

used to indicate how to interpret the configuration value. It is used mainly for
boolean values, list and hashes. See LINE_VALUE_xxx constants below for the possible values.

=back

An example of rule declaration is:

    my %dpm_config_rules_2 = (
        "ALLOW_COREDUMP" => "allowCoreDump:dpm;".LINE_FORMAT_SH_VAR.";".LINE_VALUE_BOOLEAN,
        "GLOBUS_THREAD_MODEL" => "globusThreadModel:dpm;".LINE_FORMAT_ENV_VAR,
        "DISKFLAGS" =>"DiskFlags:dpm;".LINE_FORMAT_SH_VAR.";".LINE_VALUE_ARRAY,
       );

For more comprehensive examples of rules, look at L<ncm-dpmlfc> or L<ncm-xrootd> source code in
configuration-modules-grid repository.

=cut


package CAF::RuleBasedEditor;

use strict;
use warnings;
use vars qw($EC);
$EC = LC::Exception::Context->new->will_store_all;

use parent qw(CAF::FileEditor Exporter);

use EDG::WP4::CCM::Element;

use Readonly;

use Encode qw(encode_utf8);

# Constants from FileEditor
use CAF::FileEditor qw(BEGINNING_OF_FILE ENDING_OF_FILE);


=pod

=head2 Rule Constants

The constants described here are used to build the rules. All these
constants are exported. Add the following to use them:

    use RuleBasedEditor qw(:rule_constants);

There is a different group of constants for each part of the rule.


=head3  LINE_FORMAT_xxx: general syntax of the line

=over

=item *

LINE_FORMAT_SH_VAR:         key=val (e.g. SH shell family). A comment is added at the
end of the line if it is modified by L<CAF::RuleBasedEditor>.

=item *

LINE_FORMAT_ENV_VAR:        export key=val (e.g. SH shell family). A comment is added at the
end of the line if it is modified by L<CAF::RuleBasedEditor>.


=item *

LINE_FORMAT_KW_VAL:        key val (e.g. Xrootd, Apache)

=item *
LINE_FORMAT_KW_VAL_SETENV: setenv key=val  (used by Xrootd in particular)

=item *

LINE_FORMAT_KW_VAL_SET:    set key=val  (CSH shell variable)

=back

Inline comments are not supported for the LINE_FORMAT_KW_VAL_xxx formats.

=cut

use enum qw(
    LINE_FORMAT_SH_VAR=1
    LINE_FORMAT_ENV_VAR
    LINE_FORMAT_KW_VAL
    LINE_FORMAT_KW_VAL_SETENV
    LINE_FORMAT_KW_VAL_SET
    );

=pod

=head3

LINE_VALUE_xxx: how to interpret the configuration value

=over

=item

LINE_VALUE_AS_IS: take the value as it is, do not attempt any conversion

=item

LINE_VALUE_BOOLEAN: interpret the value as a boolean rendered as C<yes> or C<no>

=item

LINE_VALUE_ARRAY: the value is an array. Rendering controlled by LINE_VALUE_OPT_xxx constants.

=item

LINE_VALUE_HASH: the value is a hash of strings. Rendering controlled by LINE_VALUE_OPT_xxx constants.

=item

LINE_VALUE_HASH_KEYS: the value is a hash whose keys are the value. Rendering similar to arrays with 
C<LINE_VALUE_ARRAY> (the key list is treated as an array).

=item

LINE_VALUE_INSTANCE_PARAMS: specific to L<ncm-xrootd>

=back

=cut

use enum qw(
    LINE_VALUE_AS_IS
    LINE_VALUE_BOOLEAN
    LINE_VALUE_ARRAY
    LINE_VALUE_HASH
    LINE_VALUE_HASH_KEYS
    LINE_VALUE_INSTANCE_PARAMS
    );

=pod

=head3 LINE_VALUE_OPT_xxx: options for rendering the value

These options mainly apply to lists and hashes and are interpreted as a bitmask.

=over

=item

LINE_KEY_OPT_PREFIX_DASH: if set, add a C<-> before the keyword when writing it in the configuration file.

=item

LINE_VALUE_OPT_SINGLE: each value in an array or keyword/value pair in a hash must be on a separate line. This results in
several instances of the same keyword (multiple lines) in the configuration file.

=item

LINE_VALUE_OPT_UNIQUE: each values are concatenated as a space-separated string

=item

LINE_VALUE_OPT_SORTED: values are sorted

=item

LINE_VALUE_OPT_SEP_COLON: use a colon between keyword and value.

=back

=cut

use enum qw(BITMASK: 
    LINE_KEY_OPT_PREFIX_DASH
    LINE_VALUE_OPT_SINGLE
    LINE_VALUE_OPT_UNIQUE
    LINE_VALUE_OPT_SORTED
    LINE_VALUE_OPT_SEP_COLON
    );

# Internal constants
Readonly my $LINE_FORMAT_DEFAULT            => LINE_FORMAT_SH_VAR;
Readonly my $LINE_QUATTOR_COMMENT           => "\t\t# Line generated by Quattor";
Readonly my $LINE_OPT_DEF_REMOVE_IF_UNDEF   => 0;
Readonly my $LINE_OPT_DEF_ALWAYS_RULES_ONLY => 0;
Readonly my $RULE_CONDITION_ALWAYS          => 'ALWAYS';
Readonly my $RULE_OPTION_SET_GLOBAL         => 'GLOBAL';


# Export constants used to build rules
# Needs to be updated when a constant is added or removed
Readonly my @RULE_CONSTANTS => qw(
    LINE_FORMAT_SH_VAR
    LINE_FORMAT_ENV_VAR
    LINE_FORMAT_KW_VAL
    LINE_FORMAT_KW_VAL_SETENV
    LINE_FORMAT_KW_VAL_SET
    LINE_VALUE_AS_IS
    LINE_VALUE_BOOLEAN
    LINE_VALUE_INSTANCE_PARAMS
    LINE_VALUE_ARRAY
    LINE_VALUE_HASH
    LINE_VALUE_HASH_KEYS
    LINE_KEY_OPT_PREFIX_DASH
    LINE_VALUE_OPT_SINGLE
    LINE_VALUE_OPT_UNIQUE
    LINE_VALUE_OPT_SORTED
    LINE_VALUE_OPT_SEP_COLON
    );


our @EXPORT_OK;
our %EXPORT_TAGS;
push @EXPORT_OK, @RULE_CONSTANTS;
$EXPORT_TAGS{rule_constants} = \@RULE_CONSTANTS;

=pod

$FILE_INTRO_xxx: constants defining the expected header lines in the configuration file

=cut

Readonly my $FILE_INTRO_PATTERN => "# This file is managed by Quattor";
Readonly my $FILE_INTRO_TXT => "# This file is managed by Quattor - DO NOT EDIT lines generated by Quattor";

# Backup file extension
Readonly my $BACKUP_FILE_EXT => ".old";

=pod

=head2 Public methods

=over

=item updateFile

Update configuration file contents,  applying configuration rules.

Arguments :
    config_rules: a hashref containing config rules corresponding to the file to build
    config_options: a hashref for configuration parameters used to build actual configuration
    options: a hashref defining options to modify the behaviour of this function

Supported entries for options hash:
    always_rules_only: if true, apply only rules with ALWAYS condition (D: false). See introduction
                       about the ALWAYS condition.
    remove_if_undef: if true, remove matching configuration line if rule condition is not met (D: false)

Return value
    sucess: 1
    argument error or error duing rule processing: undef

=cut

sub updateFile
{
    my $function_name = "updateConfigFile";
    my ($self, $config_rules, $config_options, $parser_options) = @_;

    unless ($config_rules) {
        $self->error("$function_name: 'config_rules' argument missing (internal error)");
        return;
    }
    unless ($config_options) {
        $self->error("$function_name: 'config_options' argument missing (internal error)");
        return;
    }
    unless (defined($parser_options)) {
        $self->debug(2, "$function_name: 'parser_options' undefined");
        $parser_options = {};
    }

    $self->seek_begin();

    # Check that config file has an appropriate header
    $self->add_or_replace_lines(
                                qr/^$FILE_INTRO_PATTERN/,
                                qr/^$FILE_INTRO_TXT$/,
                                $FILE_INTRO_TXT . "\n#\n",
                                BEGINNING_OF_FILE,
                               );

    my $status = $self->_apply_rules($config_rules,
                                     $config_options,
                                     $parser_options
                                    );

    return $status;
}


=pod

=back

=head2 Private methods

=over

=item formatAttrValue

This function formats an attribute value based on the value format specified.

Arguments:
    attr_value : attribute value (type interpreted based on C<value_fmt>)
    line_fmt : line format (see LINE_FORMAT_xxx constants)
    value_fmt : value format (see LINE_VALUE_xxx constants)
    value_opt : value interpretation/formatting options (bitmask, see LINE_VALUE_OPT_xxx constants)

Return value:
    A string corresponding to the value formatted according to the format specified by arguments
    or undef in case of an internal error (missing arguments)

=cut

sub _formatAttributeValue
{
    my $function_name = "_formatAttributeValue";
    my ($self, $attr_value, $line_fmt, $value_fmt, $value_opt) = @_;

    unless (defined($attr_value)) {
        $self->error("$function_name: 'attr_value' argument missing (internal error)");
        return;
    }
    unless (defined($line_fmt)) {
        $self->error("$function_name: 'list_fmt' argument missing (internal error)");
        return;
    }
    unless (defined($value_fmt)) {
        $self->error("$function_name: 'value_fmt' argument missing (internal error)");
        return;
    }
    unless (defined($value_opt)) {
        $self->error("$function_name: 'value_opt' argument missing (internal error)");
        return;
    }

    $self->debug(2,
                         "$function_name: formatting attribute value >>>$attr_value<<< (line fmt=$line_fmt, value fmt=$value_fmt, value_opt=$value_opt)"
                        );

    #FIXME: replace this if..elsif.. block by a dispatch table that would be easier to extend,
    #possibly with code out of CAF::RuleBasedEditor. Dispatch table may need to be implemented
    #in a few other methods.
    my $formatted_value;
    if ($value_fmt == LINE_VALUE_BOOLEAN) {
        $formatted_value = $attr_value ? 'yes' : 'no';

    } elsif ($value_fmt == LINE_VALUE_INSTANCE_PARAMS) {
        # LINE_VALUE_INSTANCE_PARAMS is a value format specific to XrootD (http://xrootd.org).
        # The value is a hash containing 3 keys that are used to construct a command option line.
        $formatted_value = '';    # Don't return if no matching attributes is found
                                  # Instance parameters are described in a hash
        $formatted_value .= " -l $attr_value->{logFile}"    if $attr_value->{logFile};
        $formatted_value .= " -c $attr_value->{configFile}" if $attr_value->{configFile};
        $formatted_value .= " -k $attr_value->{logKeep}"    if $attr_value->{logKeep};

    } elsif ( ($value_fmt == LINE_VALUE_ARRAY) && !($value_opt & LINE_VALUE_OPT_SINGLE) ) {
        # An array can contain several occurences of the same value. By default they are all kept
        # in the index order. Some LINE_VALUE_OPT_xxx options allow to change this default behaviour.
        $self->debug(2, "$function_name: array values received: ", join(",", @$attr_value));
        if ($value_opt & LINE_VALUE_OPT_UNIQUE) {
            my %values = map(($_ => 1), @$attr_value);
            $attr_value = [keys(%values)];
            $self->debug(2, "$function_name: array values made unique: ", join(",", @$attr_value));
        }
        # LINE_VALUE_OPT_UNIQUE implies LINE_VALUE_OPT_SORTED
        if ($value_opt & (LINE_VALUE_OPT_UNIQUE | LINE_VALUE_OPT_SORTED)) {
            $attr_value = [sort(@$attr_value)];
            $self->debug(2, "$function_name: array values sorted: ", join(",", @$attr_value));
        }
        $formatted_value = join " ", @$attr_value;

    } elsif ( $value_fmt == LINE_VALUE_HASH && !($value_opt & LINE_VALUE_OPT_SINGLE) ) {
        $self->debug(2, "$function_name: hash received with keys: ", join(",",(sort keys %$attr_value)));
        # Key/value separator (D: space)
        my $key_val_separator = ' ';
        $key_val_separator = ':' if ($value_opt & LINE_VALUE_OPT_SEP_COLON);
        # Prefix to add before key (D: none)
        my $key_prefix = '';
        $key_prefix = '-' if ($value_opt & LINE_KEY_OPT_PREFIX_DASH);
        $self->debug(2, "$function_name: key prefix: >>>$key_prefix<<<; key/value separator: $key_val_separator");
        my @tmp_values;
        foreach my $k (sort keys %$attr_value) {
            my $v = $attr_value->{$k};
            # Keys may be escaped if they contain characters like '/': unescaping a non-escaped
            # string is generally harmless.
            my $tmp = $key_prefix.unescape($k).$key_val_separator.$v;
            $self->debug(2, "$function_name: hash key/value string: '$tmp'");
            push @tmp_values, $tmp;
        }
        $formatted_value = join " ", @tmp_values;

    } elsif ($value_fmt == LINE_VALUE_HASH_KEYS) {
        $formatted_value = join " ", sort keys %$attr_value;

    } elsif ( ($value_fmt == LINE_VALUE_AS_IS) || ($value_fmt == LINE_VALUE_HASH) || ($value_fmt == LINE_VALUE_ARRAY) ) {
        # In addition to LINE_VALUE_AS_IS, do nothing when ether LINE_VALUE_HASH or LINE_VALUE_ARRAY and 
        # LINE_VALUE_OPT_SINGLE (if it is not set, this is processed before so no need to test it again). 
        $formatted_value = $attr_value;

    } else {
        $self->error("$function_name: invalid value format ($value_fmt) (internal error)");
        return;
    }

    # Quote value if necessary (only for shell variables).
    # If you do not want the line interpolated, use explicit single quotes.
    if (($line_fmt == LINE_FORMAT_SH_VAR) || ($line_fmt == LINE_FORMAT_ENV_VAR)) {
        # In the regexp, \g1 would have been better than \1 but is not supported
        # in perl 5.8 (SL5). \1 seems to achieve the same result in this context.
        if (   (($formatted_value =~ /\s+/) && ($formatted_value !~ /^(["']).*\1$/))
            || ($value_fmt == LINE_VALUE_BOOLEAN)
            || ($formatted_value eq ''))
        {
            $self->debug(2, "$function_name: quoting value '$formatted_value'");
            $formatted_value = '"' . $formatted_value . '"';
        }
    }

    $self->debug(1, "$function_name: formatted value >>>$formatted_value<<<");
    return $formatted_value;
}


=pod

=item _formatConfigLine

This function formats a configuration line using keyword and value,
according to the line format requested. Values containing spaces are
quoted if the line format is not LINE_FORMAT_KW_VAL.

Arguments :
    keyword : line keyword
    value : keyword value (can be an empty string)
    line_fmt : line format (see LINE_FORMAT_xxx constants)

Return value:
    A string corresponding to the line formatted according to line_fmt
    or undef in case of an internal error (missing arguments)

=cut

sub _formatConfigLine
{
    my $function_name = "_formatConfigLine";
    my ($self, $keyword, $value, $line_fmt) = @_;

    unless ($keyword) {
        $self->error("$function_name: 'keyword' argument missing (internal error)");
        return;
    }
    unless (defined($value)) {
        $self->error("$function_name: 'value' argument missing (internal error)");
        return;
    }
    unless (defined($line_fmt)) {
        $self->error("$function_name: 'line_fmt' argument missing (internal error)");
        return;
    }

    my $config_line = "";

    if ($line_fmt == LINE_FORMAT_SH_VAR) {
        $config_line = "$keyword=$value";
    } elsif ($line_fmt == LINE_FORMAT_ENV_VAR) {
        $config_line = "export $keyword=$value";
    } elsif ($line_fmt == LINE_FORMAT_KW_VAL_SETENV) {
        $config_line = "setenv $keyword = $value";
    } elsif ($line_fmt == LINE_FORMAT_KW_VAL_SET) {
        $config_line = "set $keyword = $value";
    } elsif ($line_fmt == LINE_FORMAT_KW_VAL) {
        $config_line = $keyword;
        $config_line .= " $value" if defined($value);
        # In this format, ensure that there is only one blank between
        # tokens and no trailing spaces as it is important in some use cases.
        $config_line =~ s/\s+/ /g;
        $config_line =~ s/\s+$//;
    } else {
        $self->error("$function_name: invalid line format ($line_fmt). Internal inconsistency.");
    }

    $self->debug(2, "$function_name: Configuration line : >>$config_line<<");
    return $config_line;
}


=pod

=item _escape_regexp_string

Help method to escape all characters with a special interpretation in the context
of a regexp.

Arguments:
    regexp_str: initial regexp string (characters not escaped)

Return value:
    string: regexp with all specail characters escaped

=cut

sub _escape_regexp_string {
    my ($self, $regexp_str) = @_;

    $regexp_str =~ s/\\/\\\\/g;
    $regexp_str =~ s/([\-\+\?\.\*\[\]()\^\$\{\}])/\\$1/g;
    $regexp_str =~ s/\s+/\\s+/g;

    return $regexp_str;
}


=item _buildLinePattern

This function builds a pattern that will match an existing configuration line for
the configuration parameter specified. The pattern built takes into account the line format.
Every whitespace in the pattern (configuration parameter) are replaced by \s+.
If the line format is LINE_FORMAT_KW_VAL, no whitespace is
imposed at the end of the pattern, as this format can be used to write a configuration
directive as a keyword with no value.

Arguments :
    config_param: parameter to update
    line_fmt: line format (see LINE_FORMAT_xxx constants)
    config_value: when defined, make it part of the pattern (used when multiple lines
                  with the same keyword are allowed)

Return value:
    A string containing the pattern to use to match the line in the file or undef
    in case of an internal error (missing argument or an invalid line format).

=cut

sub _buildLinePattern
{
    my $function_name = "_buildLinePattern";
    my ($self, $config_param, $line_fmt, $config_value) = @_;

    unless ($config_param) {
        $self->error("$function_name: 'config_param' argument missing (internal error)");
        return;
    }
    unless (defined($line_fmt)) {
        $self->error("$function_name: 'line_fmt' argument missing (internal error)");
        return;
    }
    if (defined($config_value)) {
        $self->debug(2, "$function_name: configuration value '$config_value' will be added to the pattern");
        # config_value: scape characters with a specific meaning in the regexp
        $config_value = $self->_escape_regexp_string($config_value);
    } else {
        $config_value = "";
    }

    # config_param: escape characters with a specific meaning in the regexp.
    # This is unusual but allowed to have such characters in the key part of the rules.
    $config_param = $self->_escape_regexp_string($config_param);

    # config_param is generally a keyword and in this case it contains no whitespace.
    # A special case is when config_param (the rule keyword) is used to match a line
    # without specifying a rule: in this case it may contain whitespaces. Remove strict
    # matching of them (match any type/number of whitespaces at the same position).
    # Look at %trust_config_rules in ncm-dpmlfc Perl module for an example.
    $config_param =~ s/\s+/\\s+/g;

    my $config_param_pattern;
    if ($line_fmt == LINE_FORMAT_SH_VAR) {
        $config_param_pattern = "#?\\s*$config_param=" . $config_value;
    } elsif ($line_fmt == LINE_FORMAT_ENV_VAR) {
        $config_param_pattern = "#?\\s*export\\s+$config_param=" . $config_value;
    } elsif ($line_fmt == LINE_FORMAT_KW_VAL_SETENV) {
        $config_param_pattern = "#?\\s*setenv\\s+$config_param\\s*=\\s*" . $config_value;
    } elsif ($line_fmt == LINE_FORMAT_KW_VAL_SET) {
        $config_param_pattern = "#?\\s*set\\s+$config_param\\s*=\\s*" . $config_value;
    } elsif ($line_fmt == LINE_FORMAT_KW_VAL) {
        $config_param_pattern = "#?\\s*$config_param";
        # Avoid adding a whitespace requirement if there is no config_value
        if ($config_value ne "") {
            $config_param_pattern .= "\\s+" . $config_value;
        }
    } else {
        $self->error("$function_name: invalid line format ($line_fmt). Internal inconsistency.");
        return;
    }

    return $config_param_pattern;
}


=pod

=item _commentConfigLine

This function comments out a configuration line matching the configuration parameter.
Match operation takes into account the line format.

Arguments :
    config_param: parameter to update
    line_fmt : line format (see LINE_FORMAT_xxx constants)

Return value:
    undef or 1 in case of an internal error (missing argument)

=cut

sub _commentConfigLine
{
    my $function_name = "_commentConfigLine";
    my ($self, $config_param, $line_fmt) = @_;

    unless ($config_param) {
        $self->error("$function_name: 'config_param' argument missing (internal error)");
        return 1;
    }
    unless (defined($line_fmt)) {
        $self->error("$function_name: 'line_fmt' argument missing (internal error)");
        return 1;
    }

    # Build a pattern to look for.
    my $config_param_pattern = $self->_buildLinePattern($config_param, $line_fmt);
    unless ( defined($config_param_pattern) ) {
        $self->error("$function_name: _buildLinePattern() encountered an internal error. ",
                     "Cannot comment out lines matching $config_param");
        return;
    }

    $self->debug(1, "$function_name: commenting out lines matching pattern >>>", $config_param_pattern, "<<<");
    # All matching lines must be commented out, except if they are already commented out.
    # The code used is a customized version of FileEditor::replace() that lacks support for backreferences
    # in the replacement value (here we want to rewrite the same line commented out but we don't know the
    # current line contents, only a regexp matching it).
    # FIXME: should be updated when https://github.com/quattor/CAF/issues/125 is fixed.
    my @lns;
    my $line_count = 0;
    $self->seek_begin();
    while (my $l = <$self>) {
        if ($l =~ qr/^$config_param_pattern/ && $l !~ qr/^\s*#/) {
            $self->debug(2, "$function_name: commenting out matching line >>>$l<<<");
            $line_count++;
            push(@lns, '#' . $l);
        } else {
            push(@lns, $l);
        }
    }
    if ($line_count == 0) {
        $self->debug(1, "$function_name: No line found matching the pattern");
    } else {
        $self->debug(1, "$function_name: $line_count lines commented out");
    }
    $self->set_contents(join("", @lns));

}


=pod

=item _updateConfigLine

This function does the actual update of a configuration line after doing the final
line formatting based on the line format.

Arguments :
    config_param: parameter to update
    config_value : parameter value (can be an empty string)
    line_fmt : line format (see LINE_FORMAT_xxx constants)
    multiple : if true, multiple lines with the same keyword can exist (D: false)

Return value:
    undef or 1 in case of an internal error (missing argument)

=cut

sub _updateConfigLine
{
    my $function_name = "_updateConfigLine";
    my ($self, $config_param, $config_value, $line_fmt, $multiple) = @_;

    unless ($config_param) {
        $self->error("$function_name: 'config_param' argument missing (internal error)");
        return 1;
    }
    unless (defined($config_value)) {
        $self->error("$function_name: 'config_value' argument missing (internal error)");
        return 1;
    }
    unless (defined($line_fmt)) {
        $self->error("$function_name: 'line_fmt' argument missing (internal error)");
        return 1;
    }
    unless (defined($multiple)) {
        $multiple = 0;
    }

    my $config_param_pattern;
    my $new_line = $self->_formatConfigLine($config_param, $config_value, $line_fmt);
    unless ( defined($new_line) ) {
        $self->error("$function_name: _formatConfigLine() encountered an internal error. ",
                     "Cannot update lines matching $config_param");
        return;
    }

    # Build a pattern to look for.
    # When multiple lines for the same keyword can exist, update only those matching the specific value.
    if ($multiple) {
        $self->debug(2, "$function_name: 'multiple' flag enabled");
        $config_param_pattern = $self->_buildLinePattern($config_param, $line_fmt, $config_value);
        unless ( defined($config_param_pattern) ) {
            $self->error("$function_name: _buildLinePattern() encountered an internal error. ",
                         "Cannot update lines matching $config_param");
            return;
        }
    } else {
        $config_param_pattern = $self->_buildLinePattern($config_param, $line_fmt);
        unless ( defined($config_param_pattern) ) {
          $self->error("$function_name: _buildLinePattern() encountered an internal error. ",
                       "Cannot update lines matching $config_param");
          return;
        }
        if (($line_fmt == LINE_FORMAT_KW_VAL) && defined($config_value)) {
            # For this format, if the value is defined impose a whitespace at the end to prevent matching a keyword starting
            # with the same letters.
            $config_param_pattern .= "\\s+";
        }
    }

    # Update the matching configuration lines
    if ( $new_line ) {
        my $comment = "";
        # For shell variables, add a comment at the end of the line indicating it was edited by Quattor
        # Not done for other formats as comments at the end of the line are not supported in many
        # configuration files.
        if (($line_fmt == LINE_FORMAT_SH_VAR) || ($line_fmt == LINE_FORMAT_ENV_VAR)) {
            $comment = $LINE_QUATTOR_COMMENT;
        }
        $self->debug(1, "$function_name: checking expected configuration line ($new_line) with pattern ",
                     ">>>$config_param_pattern<<<");
        $self->add_or_replace_lines(qr/^\s*$config_param_pattern/,
                                    qr/^\s*$new_line$/,
                                    $new_line . $comment . "\n",
                                    ENDING_OF_FILE,
                                   );
    }
}


=pod

=item _parse_rule

Parse a rule and return as a hash the information necessary to edit lines. If the rule
condition is not met, undef is returned. If an error occured, the hash contains more
information about the error.

Arguments :
    rule: rule to parse
    config_options: configuration parameters used to build actual configuration
    parser_options: a hashref defining options to modify the behaviour of this function

Supported entries for options hash:
    always_rules_only: if true, apply only rules with ALWAYS condition (D: false). See introduction
                       about the ALWAYS condition.
    remove_if_undef: if true, remove matching configuration line if rule condition is not met (D: false)

Return value: undef if the rule condition is not met or a hash with the following information:
    error_msg: a non empty string if an error happened during parsing
    remove_matching_lines: a boolean indicating that the matching lines must be removed
    option_sets: a list of option sets containing the attribute to use in the updated line
    attribute: the option attribute to use in the updated line

=cut

sub _parse_rule
{
    my $function_name = "_parse_rule";
    my ($self, $rule, $config_options, $parser_options) = @_;
    my %rule_info;

    unless ($rule) {
        $self->error("$function_name: 'rule' argument missing (internal error)");
        $rule_info{error_msg} = "rule parser internal error (missing argument)";
        return \%rule_info;
    }
    unless ($config_options) {
        $self->error("$function_name: 'config_options' argument missing (internal error)");
        $rule_info{error_msg} = "rule parser internal error (missing argument)";
        return \%rule_info;
    }
    unless (defined($parser_options)) {
        $self->debug(2, "$function_name: 'parser_options' undefined");
        $parser_options = {};
    }
    if (defined($parser_options->{always_rules_only})) {
        $self->debug(1, "$function_name: 'always_rules_only' option set to " . $parser_options->{always_rules_only});
    } else {
        $self->debug(1, "$function_name: 'always_rules_only' option not defined: assuming $LINE_OPT_DEF_ALWAYS_RULES_ONLY");
        $parser_options->{always_rules_only} = $LINE_OPT_DEF_ALWAYS_RULES_ONLY;
    }

    my ($condition, $tmp) = split /->/, $rule;
    # rule can be an empty string: in this case the value will remain undefined but
    # the condition will be checked in the usual way.
    if ( defined($tmp) ) {
        $rule = $tmp;
    } else {
        $condition = "";
    }
    $self->debug(1, "$function_name: condition=>>>$condition<<<, rule=>>>$rule<<<");

    # Check if only rules with ALWAYS condition must be applied.
    # ALWAYS is a special condition that is used to flag the only rules that
    # must be applied if the option always_rules_only is set. When this option
    # is not set, this condition has no effect and is just reset to an empty conditions.
    if ($parser_options->{always_rules_only}) {
        if ($condition ne $RULE_CONDITION_ALWAYS) {
            $self->debug(1, "$function_name: rule ignored ($RULE_CONDITION_ALWAYS condition not set)");
            return;
        }
    }
    if ($condition eq $RULE_CONDITION_ALWAYS) {
        $condition = '';
    }

    # Check if rule condition is met if one is defined.
    # A condition consists on the existence of a given option set (called condition set) and optionally
    # an entry in the option set, in the format condition_option:condition_set. The condition set
    # can be an option subset, expressed as set/subset/subsubset...
    if ($condition ne "") {
        $self->debug(1, "$function_name: checking condition >>>$condition<<<");

        # Condition is negated if it starts with a !: remove it from the condition value.
        # If the condition is negated, when the condition is true the rule must not be applied.
        my $negate = 0;
        if ($condition =~ /^!/) {
            $negate = 1;
            $condition =~ s/^!//;
        }
        my ($cond_attribute, $cond_option_set) = split /:/, $condition;
        unless ($cond_option_set) {
            $cond_option_set = $cond_attribute;
            $cond_attribute  = "";
        }
        $self->debug(2, "$function_name: condition option set = '$cond_option_set', ",
                     "condition attribute = '$cond_attribute', negate=$negate");
        my $cond_satisfied = 1;    # Assume condition is satisfied
        my $cond_true = 1;
        my $tmp_options = $config_options;
        foreach my $set (split(/\//, $cond_option_set)) {
            if ( $tmp_options->{$set} ) {
                $tmp_options = $tmp_options->{$set};
            } else {
                $cond_true = 0;
                last;
            }
        }
        if ($cond_attribute) {
            # Due to Perl autovivification, testing directly exists($config_options->{$cond_option_set}->{$cond_attribute}) will spring
            # $config_options->{$cond_option_set} into existence if it doesn't exist.
            $cond_true = $cond_true && exists($tmp_options->{$cond_attribute});          
        }
        if ( $negate ) {
            $cond_satisfied = 0 if $cond_true;
        } else {          
            $cond_satisfied = 0 unless $cond_true;
        }
        if (!$cond_satisfied) {
            # When the condition is not satisfied and option remove_if_undef is set,
            # remove (comment out) configuration line (if present).
            $self->debug(1, "$function_name: condition not satisfied, flag set to remove matching configuration lines");
            $rule_info{remove_matching_lines} = 1;
            return \%rule_info;
        }
    }

    my @option_sets;
    ($rule_info{attribute}, my $option_sets_str) = split /:/, $rule;
    if ($option_sets_str) {
        @option_sets = split /\s*,\s*/, $option_sets_str;
    }
    $rule_info{option_sets} = \@option_sets;

    return \%rule_info;
}


=pod

=item _apply_rules

Apply configuration rules. This method is the real workhorse of the rule-based editor.

Arguments :
    config_rules: config rules corresponding to the file to build
    config_options: configuration parameters used to build actual configuration. Note that keys in the
                    config_options hash are interpreted as escaped (generally harmless if they are not as the
                    killing sequence, '_'+ 2 hex digit, is unlikely to occur in this context. Use camel case
                    for keys to prevent problems).
    parser_options: a hash setting options to modify the behaviour of this function

Supported entries for options hash:
    always_rules_only: if true, apply only rules with ALWAYS condition (D: false)
    remove_if_undef: if true, remove matching configuration line if rule condition is not met (D: false)

Return value:
    success: 1
    undef in case of an internal error (missing argument)

=cut

sub _apply_rules
{
    my $function_name = "_apply_rules";
    my ($self, $config_rules, $config_options, $parser_options) = @_;

    unless ($config_rules) {
        $self->error("$function_name: 'config_rules' argument missing (internal error)");
        return;
    }
    unless ($config_options) {
        $self->error("$function_name: 'config_options' argument missing (internal error)");
        return;
    }
    unless (defined($parser_options)) {
        $self->debug(2, "$function_name: 'parser_options' undefined");
        $parser_options = {};
    }
    if (defined($parser_options->{remove_if_undef})) {
        $self->debug(1, "$function_name: 'remove_if_undef' option set to " . $parser_options->{remove_if_undef});
    } else {
        $self->debug(1, "$function_name: 'remove_if_undef' option not defined: assuming $LINE_OPT_DEF_REMOVE_IF_UNDEF");
        $parser_options->{remove_if_undef} = $LINE_OPT_DEF_REMOVE_IF_UNDEF;
    }


    # Loop over all config rule entries, sorted by keyword alphabetical order.
    # Config rules are stored in a hash whose key is the variable to write
    # and whose value is the rule itself.
    # If the variable name start with a '-', this means that the matching configuration
    # line must be commented out unconditionally.
    # Each rule format is '[condition->]attribute:option_set[,option_set,...];line_fmt' where
    #     condition: either a role that must be enabled or ALWAYS if the rule must be applied
    #                when 'always_rules_only' is true. A role is defined by an option set (see
    #                Description at the beginning of this file, basically a sub-hash in the config)
    #                and it is enabled if 'role_enabled' is true in the corresponding option set.
    #     option_set and attribute: attribute in option set that must be substituted
    #     line_fmt: the format to use when building the line
    # An empty rule is valid and means that the keyword part must be
    # written as is, using the line_fmt specified.

    my $rule_id = 0;
    foreach my $keyword (sort keys %$config_rules) {
        my $rule = $config_rules->{$keyword};
        $rule = '' unless defined($rule);
        $rule_id++;

        # Initialize parser_options for this rule according the default for this file
        my $rule_parsing_options = {%$parser_options};

        # Check if the keyword is prefixed by:
        #     -  a '-': in this case the corresponding line must be unconditionally
        #               commented out if it is present
        #     -  a '?': in this case the corresponding line must be commented out if
        #               it is present and the option is undefined
        my $comment_line = 0;
        if ($keyword =~ /^-/) {
            $keyword =~ s/^-//;
            $comment_line = 1;
        } elsif ($keyword =~ /^\?/) {
            $keyword =~ s/^\?//;
            $rule_parsing_options->{remove_if_undef} = 1;
            $self->debug(2, "$function_name: 'remove_if_undef' option set for the current rule");
        }

        # Split different elements of the rule
        ($rule, my $line_fmt, my $value_fmt) = split /;/, $rule;
        unless ($line_fmt) {
            $line_fmt = $LINE_FORMAT_DEFAULT;
        }
        my $value_opt;
        if ($value_fmt) {
            ($value_fmt, $value_opt) = split /:/, $value_fmt;
        } else {
            $value_fmt = LINE_VALUE_AS_IS;
        }
        unless (defined($value_opt)) {
            # $value_opt is a bitmask. Set to 0 if not specified.
            $value_opt = 0;
        }


        # If the keyword was "negated", remove (comment out) configuration line if present and enabled
        if ($comment_line) {
            $self->debug(1, "$function_name: keyword '$keyword' negated, removing/commenting configuration line");
            unless ( $self->_commentConfigLine($keyword, $line_fmt) ) {
                $self->error("$function_name: _commentConfigLine() encountered an internal error, ",
                             "lines matching '$keyword' not removed");
            }
            next;
        }


        # Parse rule if it is non empty
        my $rule_info;
        if ($rule ne '') {
            $self->debug(1, "$function_name: processing rule $rule_id (variable=>>>$keyword<<<, rule=>>>$rule<<<, fmt=$line_fmt)");
            $rule_info = $self->_parse_rule($rule, $config_options, $rule_parsing_options);
            next unless $rule_info;
            $self->debug(2, "$function_name: information returned by rule parser: " . join(" ", sort(keys(%$rule_info))));

            if (exists($rule_info->{error_msg})) {
                # FIXME: decide whether an invalid rule is considered an error or just a warning. The latter would
                # allow the caller to decide what to do exactly rather than impose an error (meaning a
                # potential dependency failure)
                $self->error("Error parsing rule >>>$rule<<<: " . $rule_info->{error_msg});
                # An invalid rule is just ignored
                next;
            } elsif ($rule_info->{remove_matching_lines}) {
                if ($rule_parsing_options->{remove_if_undef}) {
                    $self->debug(1, "$function_name: removing/commenting configuration lines for keyword '$keyword'");
                    unless ( $self->_commentConfigLine($keyword, $line_fmt) ) {
                        $self->error("$function_name: _commentConfigLine() encountered an internal error, ",
                                     "lines matching '$keyword' not removed");
                    }
                } else {
                    $self->debug(1, "$function_name: remove_if_undef not set, ignoring line to remove");
                }
                next;
            }
        }

        # Build the value to be substituted for each option set specified.
        # option_set=GLOBAL is a special case indicating a global option instead of an
        # attribute in a specific option set.
        my $config_value      = "";
        my $attribute_present = 1;
        my $config_updated    = 0;
        my @array_values;
        my %hash_values;
        if ($rule_info->{attribute}) {
            foreach my $option_set (@{$rule_info->{option_sets}}) {
                my $attr_value;
                $self->debug(1, "$function_name: retrieving '$rule_info->{attribute}' value in option set $option_set");
                if ($option_set eq $RULE_OPTION_SET_GLOBAL) {
                    if ( $config_options->{$rule_info->{attribute}} ) {
                        $attr_value = $config_options->{$rule_info->{attribute}};
                    } else {
                        $self->debug(1, "$function_name: attribute '$rule_info->{attribute}' not found ",
                                     "in global option set");
                        $attribute_present = 0;
                    }
                } else {
                    # See comment above about Perl autovivification and impact on testing attribute existence
                    if ($config_options->{$option_set} && exists($config_options->{$option_set}->{$rule_info->{attribute}})) {
                        $attr_value = $config_options->{$option_set}->{$rule_info->{attribute}};
                    } else {
                        $self->debug(1, "$function_name: attribute '$rule_info->{attribute}' not found ",
                                     "in option set '$option_set'");
                        $attribute_present = 0;
                    }
                }

                # If attribute is not defined in the present configuration, check if there is a matching
                # line in the config file for the keyword and comment it out. This requires option
                # remove_if_undef to be set.
                # Note that this will never match instance parameters and will not remove entries
                # no longer part of the configuration in a still existing LINE_VALUE_ARRAY or
                # LINE_VALUE_HASH.
                unless ($attribute_present) {
                    if ($rule_parsing_options->{remove_if_undef}) {
                        $self->debug(1, "$function_name: attribute '$rule_info->{attribute}' undefined, ",
                                     "removing configuration line");
                        $self->_commentConfigLine($keyword, $line_fmt);
                    }
                    next;
                }

                # Instance parameters are specific, as this is a hash of instances
                # with the value being a hash of parameters for the instance.
                # Also the variable name must be updated to contain the instance name.
                # One configuration line must be written/updated for each instance.
                if ($value_fmt == LINE_VALUE_INSTANCE_PARAMS) {
                    foreach my $instance (sort keys %{$attr_value}) {
                        my $params = $attr_value->{$instance};
                        $self->debug(1, "$function_name: formatting instance '$instance' parameters ($params)");
                        $config_value = $self->_formatAttributeValue($params,
                                                                     $line_fmt,
                                                                     $value_fmt,
                                                                     $value_opt,
                                                                    );
                        my $config_param = $keyword;
                        my $instance_uc  = uc($instance);
                        $config_param =~ s/%%INSTANCE%%/$instance_uc/;
                        $self->debug(2, "New variable name generated: >>>$config_param<<<");
                        $self->_updateConfigLine($config_param, $config_value, $line_fmt);
                    }
                    $config_updated = 1;
          
                } elsif ( $value_fmt == LINE_VALUE_HASH ) {
                    # Hashes are not processed immediately. First, all the values from all the options sets
                    # are collected into one hash that will be processed later according to LINE_VALUE_OPT_xxx 
                    # options specified (if any).
                    %hash_values = (%hash_values, %$attr_value)
                } elsif ($value_fmt == LINE_VALUE_ARRAY) {
                    # Arrays are not processed immediately. First, all the values from all the options sets
                    # are collected into one array that will be processed later according to LINE_VALUE_OPT_xxx
                    # options specified (if any).
                    @array_values = (@array_values, @$attr_value);
                } else {
                    $self->debug(1, "$function_name: formatting attribute '$rule_info->{attribute}' ",
                                 "value ($attr_value, value_fmt=$value_fmt)");
                    $config_value .= ' ' if $config_value;
                    $config_value .= $self->_formatAttributeValue(
                                                                  $attr_value,
                                                                  $line_fmt,
                                                                  $value_fmt,
                                                                  $value_opt,
                                                                 );
                    $self->debug(2, "$function_name: adding attribute '$rule_info->{attribute}' from ",
                                 "option set '$option_set' to value (config_value=$config_value)");
                }
            }
        } else {
            # $rule_info->{attribute} empty means an empty rule : in this case,just write the configuration param.
            $self->debug(1, "$function_name: no attribute specified in rule '$rule'");
        }

        # There is a delayed formatting of arrays and hashes after collecting all the values from all
        # the option sets in the rule. Formatting is done taking into account the relevant
        # LINE_VALUE_OPT_xxx specified (bitmask).
        if ($value_fmt == LINE_VALUE_ARRAY) {
            if ($value_opt & LINE_VALUE_OPT_SINGLE) {
                # With this value format, several lines with the same keyword are generated,
                # one for each array value (if value_opt is not LINE_VALUE_OPT_SINGLE, all
                # the values are concatenated on one line).
                $self->debug(1, "$function_name: formatting (array) attribute '",
                             $rule_info->{attribute}, "' as LINE_VALUE_OPT_SINGLE");
                foreach my $val (@array_values) {
                    $config_value = $self->_formatAttributeValue(
                                                                 $val,
                                                                 $line_fmt,
                                                                 $value_fmt,
                                                                 $value_opt,
                                                                );
                    $self->_updateConfigLine($keyword, $config_value, $line_fmt, 1);
                }
                $config_updated = 1;
            } else {
                $config_value = $self->_formatAttributeValue(\@array_values,
                                                             $line_fmt,
                                                             $value_fmt,
                                                             $value_opt,
                                                            );
            }
        
        } elsif ( $value_fmt == LINE_VALUE_HASH ) {
            # With this value format, either several lines with the same keyword are generated,
            # one for each key/value pair if LINE_VALUE_OPT_SINGLE is set or all the key/value
            # pairs are concatenated to create the value.
            if ( $value_opt & LINE_VALUE_OPT_SINGLE ) {
                foreach my $k (sort keys %hash_values) {
                    my $v = $hash_values{$k};
                    # Value is made by joining key and value as a string
                    # Keys may be escaped if they contain characters like '/': unescaping a non-escaped
                    # string is generally harmless.
                    my $tmp = unescape($k)." $v";
                    $self->debug(1,"$function_name: formatting (string hash) attribute '".$rule_info->{attribute}."' value ($tmp, value_fmt=$value_fmt)");
                    $config_value = $self->_formatAttributeValue($tmp,
                                                                 $line_fmt,
                                                                 $value_fmt,
                                                                 $value_opt,
                                                                );
                    $self->_updateConfigLine($keyword, $config_value, $line_fmt, 1);
                }
                $config_updated = 1;

            } else {
                $config_value = $self->_formatAttributeValue(\%hash_values,
                                                             $line_fmt,
                                                             $value_fmt,
                                                             $value_opt,
                                                            );
            }
        }

        # Instance parameters, string hashes have already been written
        if (!$config_updated && $attribute_present) {
            $self->_updateConfigLine($keyword, $config_value, $line_fmt);
        }

    }

}


=pod

=back

=cut

1;    # Required for PERL modules
