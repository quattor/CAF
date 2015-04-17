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

use Readonly;

Readonly::Scalar my $DEFAULT_INCLUDE_PATH => '/usr/share/templates/quattor';
Readonly::Scalar my $DEFAULT_RELPATH => 'metaconfig';
Readonly::Scalar my $DEFAULT_USECACHE => 1;

Readonly::Scalar my $DEFAULT_TT_STRICT => 0;
Readonly::Scalar my $DEFAULT_TT_RECURSION => 1;

use base qw(CAF::Object);

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

C<contents> is a hash reference holding the contents to pass to the rendering module.

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
    # allow module aware contents changes
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
sub select_module_method {

    my ($self) = @_;

    if ($self->{module} !~ m{^([\w+/\.\-]+)$}) {
        return $self->fail("Invalid configuration module: $self->{module}");
    }

    my $method;

    my $method_name = "render_".lc($1);
    if ($method = $self->can($method_name)) {
        $self->debug(3, "Rendering module $self->{module} with method $method_name");
    } else {
        $method = \&tt;
        $self->debug(3, "Using Template::Toolkit to render module $self->{module}");
    }

    return $method;
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


sub render_yaml
{
    my ($self, $cfg) = @_;

    return YAML::XS::Dump($self->{contents});
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


sub render_general
{
    my ($self) = @_;

    my $c = Config::General->new(-SaveSorted => 1); # sort output
    return $c->save_string($self->{contents});
}


1;

