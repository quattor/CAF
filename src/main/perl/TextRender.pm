#${PMpre} CAF::TextRender${PMpost}

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
use Module::Load;

use parent qw(CAF::ObjectText Exporter);

our @EXPORT_OK = qw($YAML_BOOL $YAML_BOOL_PREFIX);

use Readonly;

# Update includepath pod section when updated.
Readonly::Array my @DEFAULT_INCLUDE_PATHS => qw(/usr/share/templates/quattor);
# Update relpath pod section when updated.
Readonly::Scalar my $DEFAULT_RELPATH => 'metaconfig';

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
# For YAML false, perl false (i.e. 0 == 1) could be used, but since we need
# the special trickery for true, why not also use this for false.
# The YAML_BOOL is a hashref holding the YAML::XS true and false,
# use e.g. $YAML_BOOL->{yes} for the true value (don't use true as key name,
# some parsers make it the internal true value too)
Readonly our $YAML_BOOL => Load("yes: true\nno: false\n");
# However, making a hashref destroys this structure;
# so also supporting a simple search and replace method for now.
# The search and replace only supports $YAML_BOOL_PREFIX(true|false),
# all other matches are considered a failure.
Readonly our $YAML_BOOL_PREFIX => '___CAF_TEXTRENDER_IS_YAML_BOOLEAN_';

# Given C<includepaths> argument, return an array reference of include paths
# If C<includepaths> as a string is ':'-splitted to a list of paths
# If C<includepaths> is undef, the default DEFAULT_INCLUDE_PATHS is used.
# Returns undef if C<includepaths> is neither one of the above nor an arrayref.
sub _convert_includepaths
{
    my $includepaths = shift;

    return \@DEFAULT_INCLUDE_PATHS if (! defined($includepaths));

    my $ref = ref($includepaths);
    if ($ref) {
        if($ref eq 'ARRAY') {
            return $includepaths;
        } else {
            # TODO howto raise error?
            return;
        }
    } else {
        return [split(':', $includepaths)]
    }
}


=pod

=head1 NAME

CAF::TextRender - Class for rendering structured text

=head1 SYNOPSIS

    use CAF::TextRender;

    my $module = 'tiny';
    my $trd = CAF::TextRender->new($module, $contents, log => $self);
    print "$trd"; # stringification

    $module = "yaml";
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

=over

=item json

JSON format (using C<JSON::XS>) (JSON true and false have to be resp. C<\1> and c<\0>)

=item yaml

YAML (using C<YAML::XS>) (YAML true and false, either resp. C<$YAML_BOOL->{yes}> and
C<$YAML_BOOL->{no}>; or the strings C<$YAML_BOOL_PREFIX."true"> and
C<$YAML_BOOL_PREFIX."false"> (There are known problems with creating hashrefs using the
C<$YAML_BOOL->{yes}> value for true; Perl seems to mess up the structure when creating
the hashrefs))

=item properties

Java properties format (using C<Config::Properties>),

=item tiny

.INI format (using C<Config::Tiny>)

=back

(Previously available module <general> was removed in 15.12.
Component writers needing this functionality can use
the B<CCM::TextRender> subclass instead).

Or, for any other value, C<Template::Toolkit> is used, and the C<module> then indicates
the relative path of the template to use.

=item C<contents>

C<contents> is a hash reference holding the contents to pass to the rendering module.

=back

It takes some extra optional arguments:

=over

=item C<log>, C<eol> and C<usecache>

Handled by C<_initialize_textopts> from B<CAF::ObjectText>

=item C<includepath>

The basedirectory for TT template files, and the INCLUDE_PATH
for the Template instance. The C<includepath> is either a string
(i.e. ':'-separated list of paths), an arrayref (of multiple include paths)
or undef (the default '/usr/share/templates/quattor' is used).

=item C<relpath>

The relative path w.r.t. the includepath to look for TT template files.
This relative path should not be part of the module name, however it
is not the INCLUDE_PATH. (In particular, any TT C<INCLUDE> statement has
to use it as the relative basepath).
If C<relpath> is undefined, the default 'metaconfig' is used. If you do not
have a subdirectory in the includepath, use an empty string.

=item C<ttoptions>

A hash-reference C<ttoptions> with Template Toolkit options,
except for INCLUDE_PATH which is forced via C<includepath> option.
By default, STRICT (default 0) and RECURSION (default 1) are set.

=back

=back

=cut

sub _initialize
{
    my ($self, $module, $contents, %opts) = @_;

    %opts = () if !%opts;

    # sets e.g. $self->{log}
    $self->_initialize_textopts(%opts);

    $self->{module} = $module;
    $self->{contents} = $contents;

    $self->{includepath} = _convert_includepaths($opts{includepath});
    $self->{relpath} = defined($opts{relpath}) ? $opts{relpath} : $DEFAULT_RELPATH;
    $self->verbose("Using includepath ", join(':', @{$self->{includepath}}));
    $self->verbose("Using relpath '$self->{relpath}'");

    # Set TT options
    $self->{ttoptions} = {
        STRICT => $DEFAULT_TT_STRICT,
        RECURSION => $DEFAULT_TT_RECURSION,
    };
    while (my ($key, $value) = each %{$opts{ttoptions}}) {
        $self->{ttoptions}->{$key} = $value;
    }

    # set render method
    ($self->{method}, $self->{method_is_tt}) = $self->select_module_method();

    # set contents, after module is selected (some modules
    # allow module aware contents changes)
    $self->{contents} = $self->make_contents();

    return SUCCESS;
}


# Convert the C<module> in an absolute template path.
# The extension C<.tt> is optional for the module, but mandatory for
# the actual template file.
# Returns undef in case of error.
sub sanitize_template
{
    my ($self) = @_;

    my $tplname_orig = $self->{module};

    if (file_name_is_absolute($tplname_orig)) {
        return $self->fail("Must have a relative template name (got $tplname_orig)");
    }

    if ($tplname_orig !~ m{\.tt$}) {
        $tplname_orig .= ".tt";
    }

    # module is relative to relpath
    my $relpath = $self->{relpath} ? "$self->{relpath}/" : "";

    return $self->fail("No includepath defined.") if (! defined($self->{includepath}));

    my $includepaths_txt = join(',', @{$self->{includepath}});
    $self->debug(3, "We must ensure that all templates lie below $includepaths_txt.");

    my @failed_msg;
    foreach my $includepath (@{$self->{includepath}}) {
        my $abs_tplname = "$includepath/$relpath$tplname_orig";
        my $tplname = abs_path($abs_tplname);
        if ($tplname && -f $tplname) {
            # untaint and sanitycheck
            my $reg = "$includepath/($relpath.*)";
            if ($tplname =~ m{^$reg$}) {
                my $result_template = $1;
                $self->verbose("Using template $result_template for module $self->{module}");
                return $result_template;
            } else {
                return $self->fail("Insecure template name $tplname.",
                                   " Final template must be under one of",
                                   " $includepaths_txt/$relpath");
            }
        } else {
            # abs_path returns undef on non-existing path; use this to avoid uninitialized warning
            $tplname = '<undef>' if ! defined($tplname);
            push(@failed_msg, "$tplname (abs_path of $abs_tplname)");
        }
    }

    return $self->fail("Non-existing template names: ", join(',', @failed_msg));
}

# Return a Template::Toolkit instance
# (from ncm-ncd Component module)
# Mandatory argument C<includepath> to set the INCLUDE_PATH
# Other options can be passed via named arguments.
sub get_template_instance
{
    my ($includepaths, %opts) = @_;

    $includepaths = _convert_includepaths($includepaths);

    return if (! defined($includepaths));

    $Template::Stash::PRIVATE = undef;

    # force the includepath
    $opts{INCLUDE_PATH} = $includepaths;

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
# Also returns a boolean to indicate the selected method is the fallback C<tt>.
sub select_module_method {

    my ($self) = @_;

    if ($self->{module} !~ m{^([\w+/\.\-]+)$}) {
        return $self->fail("Invalid configuration module: $self->{module}");
    }

    my $method;
    my $method_is_tt = 0;

    my $method_name = "render_".lc($1);
    if ($method = $self->can($method_name)) {
        $self->debug(3, "Rendering module $self->{module} with method $method_name");
    } else {
        $method = \&tt;
        $method_is_tt = 1;
        $self->debug(3, "Using Template::Toolkit to render module $self->{module}");
    }

    return $method, $method_is_tt;
}

# Return the validated contents (or allow subclasses to do so).
# The base implementation verifies if the contents are a hashref.
# Otherwise it fails
sub make_contents
{
    my ($self) = @_;

    my $contents;

    my $ref = ref($self->{contents});

    if ($ref && ($ref eq 'HASH')) {
        return $self->{contents};
    } else {
        return $self->fail("Contents is not a hashref ",
                           "(ref ", (defined($ref) ? "$ref" : "<undef>"), ")");
    }
}

# Test for failures due to invalid module and/or
# invalid contents.
sub _get_text_test
{
    my ($self) = @_;

    # method undefined in case of invalid module
    return if (!defined($self->{method}));

    # contents undefined in case of invalid contents
    return if (!defined($self->{contents}));

    return SUCCESS;
}

# The text is produced by calling the render method
sub _get_text
{
    my ($self) = @_;

    my $msg = "Failed to render with module $self->{module}";
    my $res = $self->{method}->($self);

    return ($res, $msg);
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

    local $@;
    eval {
        load $module;
    };
    if ($@) {
        return $self->fail("Unable to load $module: $@");
    }
    return 1;
}


sub render_json
{
    my ($self) = @_;

    # We should only support hash or array refs (see JSON::XS allow_nonref option)
    # JSON::XS croaks if not handled properly
    my $ref = ref($self->{contents});
    if ($ref eq 'HASH' || $ref eq 'ARRAY') {
        my $j = JSON::XS->new();
        $j->canonical(1); # sort the keys, to create reproducable results
        return $j->encode($self->{contents});
    } else {
        return $self->fail("contents for JSON rendering must be ",
                           "hash or array reference (got '$ref' instead)");
    }
}

# Search and replace the YAML boolean PREFIX
# Private function, call directly for testing only
sub _yaml_replace_boolean_prefix
{
    my ($self, $yamltxt) = @_;
    # Implicit quoting could be enabled in the YAML::XS Dump.
    $yamltxt =~ s/('|")?$YAML_BOOL_PREFIX(true|false)\1?/$2/g;
    if ($yamltxt =~ m/$YAML_BOOL_PREFIX/) {
        # The YAML boolean PREFIX should only be used with the regexp above
        # If there is any prefix match left, this is considered a failure.
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
    my ($self, $cfg) = @_;

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


1;
