# ${license-info}
# ${developer-info}
# ${author-info}
# ${build-info}

package CAF::TextRender;

use strict;
use warnings;
use LC::Exception qw (SUCCESS);
use CAF::FileWriter;
use Cwd qw(abs_path);
use File::Spec::Functions qw(file_name_is_absolute);

# Support for TT (the default/fallback)
use Template;
use Template::Stash;

# Mandatory support for other formats
use JSON::XS;
use YAML::XS;
use Config::Properties;
use Config::Tiny;
use Config::General;

use base qw(CAF::Object Exporter);

our @EXPORT_OK = qw(%ELEMENT_CONVERT);

use Readonly;

Readonly::Scalar my $DEFAULT_INCLUDE_PATH => '/usr/share/templates/quattor';
Readonly::Scalar my $DEFAULT_RELPATH => 'metaconfig';
Readonly::Scalar my $DEFAULT_USECACHE => 1;

Readonly::Scalar my $DEFAULT_TT_STRICT => 0;
Readonly::Scalar my $DEFAULT_TT_RECURSION => 1;

# YAML::XS boolean true has the most bizarre internal structure
# (a 0 length struct with value 1 according to Devel::Peek)
#     perl -MYAML::XS -e 'use Devel::Peek qw(); $x=Load("a: true\n");
#                         print Devel::Peek::Dump($x->{a}),"\n";'
#     SV = PVNV(0x1ad9cf0) at 0x1ad81b8
#       REFCNT = 2147483642
#       FLAGS = (IOK,NOK,POK,READONLY,pIOK,pNOK,pPOK)
#       IV = 1
#       NV = 1
#       PV = 0x33c99670c2 "1"
#       CUR = 1
#       LEN = 0
#
# for YAML false perl false (i.e. 0 == 1) could be used, but since we need
# the special trickery for true, why not also use this for false.
# (don't use true as key name, some parsers make it the internal true value too)
# This retruns a hashref, use e.g. $YAML_BOOL->{yes} for the true value.
Readonly our $YAML_BOOL => Load("yes: true\nno: false\n");
# However, making a hashref destroys this structure;
# so using a simple search and replace method for now.
Readonly our $YAML_BOOL_PREFIX => '___CAF_TEXTRENDER_IS_YAML_BOOLEAN_';

Readonly::Hash our %ELEMENT_CONVERT => {
    'json_boolean' => sub {
        my $value = shift;
        return $value ? \1 : \0;
    },
    'yaml_boolean' => sub {
        my $value = shift;
        #return $value ? $YAML_BOOL->{yes} : $YAML_BOOL->{no};
        return $YAML_BOOL_PREFIX .
            ($value ? 'true' : 'false');
    },
    'yesno_boolean' => sub {
        my $value = shift;
        return $value ? 'yes' : 'no';
    },
    'YESNO_boolean' => sub {
        my $value = shift;
        return $value ? 'YES' : 'NO';
    },
    'doublequote_string' => sub {
        my $value = shift;
        return "\"$value\"";
    },
    'singlequote_string' => sub {
        my $value = shift;
        return "'$value'";
    },
};

use overload ('""' => '_stringify');

=pod

=head1 NAME

CAF::TextRender - Class for rendering structured text

=head1 SYNOPSIS

    use CAF::TextRender;

    my $module = 'tiny';
    my $trd = CAF::TextRender->new($module, $contents, log => $self);
    print "$trd"; # stringification

    $module = "general";
    $trd = CAF::TextRender->new($module, $contents, log => $self);
    # return CAF::FileWriter instance (rendered text already added)
    my $fh = $trd->filewriter('/some/path');
    die "Problem rendering the text" if (!defined($fh));
    $fh->close();

=head1 DESCRIPTION

This class simplyfies the generation of structured text like config files.
(It is based on 14.8.0 ncm-metaconfig).

=cut

=head2 Private methods

=over

=item C<_initialize>

Initialize the process object. Arguments:

=over

=item C<module>

The rendering module to use: either one of the following reserved values
C<json> (using C<JSON::XS>),
C<yaml> (using C<YAML::XS>),
C<properties> (using C<Config::Properties>),
C<tiny> (using C<Config::Tiny>),
C<general> (using C<Config::General>)

Or, for any other value, C<Template::Toolkit> is used, and the C<module> then indicates
the relative path of the template to use.

=item C<contents>

C<contents> is either a hash reference holding the contents to pass to the rendering module;
or a C<EDG::WP4::CCM:Element> instance, on which C<getTree> is called with any C<element>
options.

=back

It takes some extra optional arguments:

=over

=item C<log>

A C<CAF::Reporter> object to log to.

=item C<includepath>

The basedirectory for TT template files, and the INCLUDE_PATH
for the Template instance.

=item C<relpath>

The relative path w.r.t. the includepath to look for TT template files.
This relative path should not be part of the module name, however it
is not the INCLUDE_PATH. (In particular, any TT C<INCLUDE> statement has
to use it as the relative basepath).

=item C<eol>

If C<eol> is true, the rendered text will be verified that it ends with
an end-of-line, and if missing, a newline character will be added.
By default, C<eol> is true (this is text rendering afterall).

C<eol> set to false will not strip trailing newlines (use C<chomp>
or something similar for that).

=item C<usecache>

If C<usecache> is false, the text is always re-rendered.
Default is to cache the rendered text (C<usecache> is true).

=item C<ttoptions>

A hash-reference C<ttoptions> with Template Toolkit options,
except for INCLUDE_PATH which is forced via C<includepath> option.
By default, STRICT (default 0) and RECURSION (default 1) are set.

=item C<element>

A hashref holding any C<getTree> options to pass. These can be the
anonymous convert methods C<convert_boolean>, C<convert_string>,
C<convert_long> and C<convert_double>; or one of the
predefined convert methods (key is the name, value a boolean
wheter or not to use them). The C<convert_> methods take precedence over
the predefined ones in case there is any overlap.

The predefined convert methods are:

=over

=item json

Enable JSON output, in particular JSON boolean (the other types should
already be in proper format). This is enabled when the json module is
used.

=item yaml

Enable YAML output, in particular YAML boolean (the other types should
already be in proper format). This is enabled when the yaml module is
used.

=item yesno

Convert boolean to (lowercase) 'yes' and 'no'.

=item YESNO

Convert boolean to (uppercase) 'YES' and 'NO'.

=item doublequote

Convert string to doublequoted string.

=item singlequote

Convert string to singlequoted string.

=item depth

Only return the next C<depth> levels of nesting (and use the
Element instances as values). A C<depth == 0> is the element itself,
C<depth == 1> is the first level, ...

Default or depth C<undef> returns all levels.

=back

=back

=back

=cut

sub _initialize
{
    my ($self, $module, $contents, %opts) = @_;

    %opts = () if !%opts;

    $self->{module} = $module;
    $self->{contents} = $contents;

    $self->{log} = $opts{log} if $opts{log};

    $self->{elementopts} = $opts{element};

    if (exists($opts{eol})) {
        $self->{eol} = $opts{eol};
        $self->verbose("Set eol to $self->{eol}");
    } else {
        # Default to true
        $self->{eol} = 1;
    };

    $self->{includepath} = $opts{includepath} || $DEFAULT_INCLUDE_PATH;
    $self->{relpath} = $opts{relpath} || $DEFAULT_RELPATH;
    $self->verbose("Using includepath $self->{includepath}");
    $self->verbose("Using relpath $self->{relpath}");

    if(exists($opts{usecache})) {
        $self->{usecache} = $opts{usecache};
    } else {
        $self->{usecache} = $DEFAULT_USECACHE;
    }
    $self->verbose("No caching") if (! $self->{usecache});

    # Set TT options
    $self->{ttoptions} = {
        STRICT => $DEFAULT_TT_STRICT,
        RECURSION => $DEFAULT_TT_RECURSION,
    };
    while (my ($key, $value) = each %{$opts{ttoptions}}) {
        $self->{ttoptions}->{$key} = $value;
    }

    # set render method
    $self->{method} = $self->select_module_method();

    # set contents, after module is selected (some modules trigger
    # predefined element options)
    $self->{contents} = $self->make_contents();

    return SUCCESS;
}


# Handle failures. Stores the error message and log it verbose and
# returns undef. All failures should use 'return $self->fail("message");'.
# No error logging should occur in this module.
sub fail
{
    my ($self, @messages) = @_;
    $self->{fail} = join('', @messages);
    $self->verbose("FAIL: ", $self->{fail});
    return;
}


# Convert the C<module> in an absolute template path.
# The extension C<.tt> is optional for the module, but mandatory for
# the actual template file.
# Returns undef in case of error.
sub sanitize_template
{
    my ($self) = @_;

    my $tplname = $self->{module};

    if (file_name_is_absolute($tplname)) {
        return $self->fail("Must have a relative template name (got $tplname)");
    }

    if ($tplname !~ m{\.tt$}) {
        $tplname .= ".tt";
    }

    # module is relative to relpath
    $tplname = "$self->{relpath}/$tplname" if $self->{relpath};

    $self->debug(3, "We must ensure that all templates lie below $self->{includepath}");
    my $abs_tplname = "$self->{includepath}/$tplname";
    $tplname = abs_path($abs_tplname);
    if (!$tplname || !-f $tplname) {
        # abs_path returns undef on non-existing path; use this to avoid uninitialized warning
        $tplname = '<undef>' if ! defined($tplname);
        return $self->fail("Non-existing template name $tplname given (abs_path of $abs_tplname)");
    }

    # untaint and sanitycheck
    # TODO empty relpath will never match
    my $reg = "$self->{includepath}/($self->{relpath}/.*)";
    if ($tplname =~ m{^$reg$}) {
        my $result_template = $1;
        $self->verbose("Using template $result_template for module $self->{module}");
        return $result_template;
    } else {
        return $self->fail("Insecure template name $tplname. Final template must be under $self->{includepath}/$self->{relpath}");
    }
}

# Return a Template::Toolkit instance
# (from ncm-ncd Component module)
# Mandatory argument C<includepath> to set the INCLUDE_PATH
# Other options can be passed via named arguments.
sub get_template_instance
{
    my ($includepath, %opts) = @_;
    $Template::Stash::PRIVATE = undef;

    # force the includepath
    $opts{INCLUDE_PATH} = $includepath;

    my $template = Template->new(%opts);
    return $template;
}

# Fallback/default rendering method based on C<Template::Toolkit>.
# C<module> is a relative path to a TT template.
sub tt
{
    my ($self) = @_;

    my $sane_tpl = $self->sanitize_template();

    # failire already handled in sanitize_template
    return if (!$sane_tpl);

    my $tpl = get_template_instance($self->{includepath}, %{$self->{ttoptions}});

    my $str;
    if (!$tpl->process($sane_tpl, $self->{contents}, \$str)) {
        return $self->fail("Unable to process template for file $sane_tpl (module $self->{module}: ",
                           $tpl->error());
    }
    return $str;
}

# Return the rendering method corresponding with the C<module>
# If no reserved method name C<render_$module> is found, fallback to
# C<Template::Toolkit based> C<tt> method is set.
sub select_module_method
{
    my ($self) = @_;

    if ($self->{module} !~ m{^([\w+/\.\-]+)$}) {
        return $self->fail("Invalid configuration module: $self->{module}");
    }

    my $method;

    my $method_name = "render_".lc($1);
    if ($method = $self->can($method_name)) {
        $self->debug(3, "Rendering module $self->{module} with method $method_name");
        if ($method_name eq 'render_json') {
            $self->{elementopts}->{json} = 1;
        } elsif ($method_name eq 'render_yaml') {
            $self->{elementopts}->{yaml} = 1;
        }
    } else {
        $method = \&tt;
        $self->debug(3, "Using Template::Toolkit to render module $self->{module}");
    }

    return $method;
}

# Return the validated contents. Either the contents are a hashref
# (in that case they are left untouched) or a C<EDG::WP4::CCM::Element> instance
# in which case C<getTree> is called together with the relevant C<elementopts>
sub make_contents
{
    my ($self) = @_;

    my $contents;

    my $ref = ref($self->{contents});

    if($ref && ($ref eq "HASH")) {
        $contents = $self->{contents};
    } elsif ($ref && UNIVERSAL::can($self->{contents},'can') &&
             $self->{contents}->isa('EDG::WP4::CCM::Element')) {
        # Test for a blessed reference with UNIVERSAL::can
        # UNIVERSAL::can also return true for scalars, so also test
        # if it's a reference to start with
        $self->debug(3, "Contents is a Element instance");
        my $depth = $self->{elementopts}->{depth};

        my %opts;
        # predefined convert_
        if ($self->{elementopts}->{json}) {
            $opts{convert_boolean}  = $ELEMENT_CONVERT{json_boolean};
        } elsif ($self->{elementopts}->{yaml}) {
            $opts{convert_boolean}  = $ELEMENT_CONVERT{yaml_boolean};
        } else {
            if ($self->{elementopts}->{yesno}) {
                $opts{convert_boolean}  = $ELEMENT_CONVERT{yesno_boolean};
            } elsif ($self->{elementopts}->{YESNO}) {
                $opts{convert_boolean}  = $ELEMENT_CONVERT{YESNO_boolean};
            }
            if ($self->{elementopts}->{doublequote}) {
                $opts{convert_string}  = $ELEMENT_CONVERT{doublequote_string};
            } elsif ($self->{elementopts}->{singlequote}) {
                $opts{convert_string}  = $ELEMENT_CONVERT{singlequote_string};
            }
        }

        # The convert_ precede the predefined ones
        foreach my $type (qw(boolean string long double)) {
            my $am_name = "convert_$type";
            my $am = $self->{elementopts}->{$am_name};
            $opts{$am_name} = $am if (defined ($am));
        }

        $contents = $self->{contents}->getTree($depth, %opts);
    } else {
        return $self->fail("Contents passed is neither a hashref or ",
                           "a EDG::WP4::CCM::Element instance ",
                           "(ref ", ref($self->{contents}), ")");
    }

    return $contents;
}

=pod

=head2 C<get_text>

C<get_text> renders and returns the text.

In case of a rendering error, C<get_text> returns C<undef>
(and an error is logged if log instance is present).
This is the main difference from the auto-stringification that
returns an empty string in case of a rendering error.

By default, the rendered result is cached. To force re-rendering the text,
clear the current cache by passing C<1> as first argument
(or disable caching completely with the option C<usecache>
set to false during the <CAF::TextRender> initialisation).

=cut

sub get_text
{
    my ($self, $clearcache) = @_;

    # method undefined in case of invalid module
    return if (!defined($self->{method}));

    # contents undefined in case of invalid contents
    return if (!defined($self->{contents}));

    if ($clearcache) {
        $self->verbose("get_text clearing cache");
        delete $self->{_cache};
    };

    if (exists($self->{_cache})) {
        $self->debug(1, "Returning the cached value");
        return $self->{_cache}
    };

    my $res = $self->{method}->($self);

    if (defined($res)) {
        if($self->{eol} && $res !~ m/\n$/) {
            $self->verbose("eol set, and rendered text was missing final newline. adding newline.");
            $res .= "\n";
        }
        if($self->{usecache}) {
            $self->{_cache} = $res;
        };
        return $res;
    } else {
        my $msg = "Failed to render with module $self->{module}";
        $msg .= ": $self->{fail}" if ($self->{fail});
        return $self->fail($msg);
    }
}

# Handle possible undef from get_text to avoid 'Use of uninitialized value' warnings
sub _stringify
{
    my ($self) = @_;
    # Always default cache behaviour
    my $text = $self->get_text();
    if(defined($text)) {
        return $text;
    } else {
        return "";
    }
}

=pod

=head2 C<filewriter>

Create and return an open C<CAF::FileWriter> instance with
first argument as the filename. If the rendering fails,
C<undef> is returned.

The rendered text is added to the filehandle.
It's up to the consumer to cancel
and/or close the instance

All C<CAF::FileWriter> initialisation options are supported
and passed on. (If no C<log> option is provided,
 the one from the C<CAF::TextRender> instance is passed).

Two new options C<header> and C<footer> are supported
 to resp. prepend and append to the rendered text.

If C<eol> was set during initialisation, the header and footer
will also be checked for EOL.
(EOL is still added to the rendered text if
C<eol> is set during initialisation, even if there is a footer
defined.)

=cut

sub filewriter
{
    my ($self, $file, %opts) = @_;

    # use get_text, not stringification to handle render failure
    my $text = $self->get_text();
    return if (!defined($text));

    my $header = delete $opts{header};
    my $footer = delete $opts{footer};

    $opts{log} = $self if(!exists($opts{log}));

    my $cfh = CAF::FileWriter->new($file, %opts);

    if (defined($header)) {
        print $cfh $header;

        if($self->{eol} && $header !~ m/\n$/) {
            $self->verbose("eol set, and header was missing final newline. adding newline.");
            print $cfh "\n";
        };
    };

    print $cfh $text;

    if (defined($footer)) {
        print $cfh $footer;

        if($self->{eol} && $footer !~ m/\n$/) {
            $self->verbose("eol set, and footer was missing final newline. adding newline.");
            print $cfh "\n";
        };
    };

    return $cfh
}

# Given Perl C<module>, load it.
#
# To be used like '$self->load_module("External::Module") or return;'
# in any new render_X method that does and/or can not have the module
# to use as a mandatory module (via a 'use External::Module;').
# When adding such functionality, it will be left to the consumer to enforce
# the dependecy in the packaging (e.g. by setting a 'use External::Module;'
# in the consumer code or by adding a '<require>' entry in the maven pom.xml)
sub load_module
{
    my ($self, $module) = @_;

    $self->verbose("Loading module $module");

    eval "use $module";
    if ($@) {
        return $self->fail("Unable to load $module: $@");
    }
    return 1;
}


sub render_json
{
    my ($self) = @_;

    my $j = JSON::XS->new();
    $j->canonical(1); # sort the keys, to create reproducable results
    return $j->encode($self->{contents});
}

# search and replace the YAML boolean PREFIX
# private function, call diretcly for testing only
sub _yaml_replace_boolean_prefix
{
    my ($self, $yamltxt) = @_;
    # Implicit quoting could be enabled in the YAML::XS Dump.
    $yamltxt =~ s/('|")?$YAML_BOOL_PREFIX(true|false)\1?/$2/g;
    if ($yamltxt =~ m/$YAML_BOOL_PREFIX/) {
        # just in case
        return $self->fail("Failed to search and replace the YAML_BOOL_PREFIX $YAML_BOOL_PREFIX");
    };
    return $yamltxt;
}

sub render_yaml
{
    my ($self, $cfg) = @_;

    my $txt = YAML::XS::Dump($self->{contents});
    return $self->_yaml_replace_boolean_prefix($txt);
}

# Warning: the rendered text has a header with localtime(),
# so the contents will always appear changed.
sub render_properties
{
    my ($self) = @_;

    # recent versions of Config::Properties support order => 'alpha'
    # for aplabetic key sorting when writing
    # Default is 'keep', based on linenumbers. In the usage here, it
    # means first parsed entry is on first line. For an unordered hash,
    # this is not predicatable/reproducable. So we will sort the linenumbers
    # and use linenumber sorted output.
    my $config = Config::Properties->new(order => 'keep');
    $config->setFromTree($self->{contents});

    # force linenumbers
    my $line=1;
    foreach my $k (sort(keys %{$config->{properties}})) {
        $config->{property_line_numbers}{$k} = $line;
        $line++;
    }

    return $config->saveToString();
}


sub render_tiny
{
    my ($self) = @_;

    my $c = Config::Tiny->new();
    while (my ($k, $v) = each(%{$self->{contents}})) {
        if (ref($v)) {
            $c->{$k} = $v;
        } else {
            $c->{_}->{$k} = $v;
        }
    }
    return $c->write_string();
}


sub render_general
{
    my ($self) = @_;

    my $c = Config::General->new(-SaveSorted => 1); # sort output
    return $c->save_string($self->{contents});
}


1;
