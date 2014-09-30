# ${license-info}
# ${developer-info
# ${author-info}
# ${build-info}
#
#
# CAF::TextRender class

package CAF::TextRender;

use strict;
use warnings;
use LC::Exception qw (SUCCESS);
use CAF::FileWriter;
use Cwd qw(abs_path);
use File::Spec::Functions qw(file_name_is_absolute);
use Template;
use Template::Stash;

use Readonly;

Readonly::Scalar my $DEFAULT_INCLUDE_PATH => '/usr/share/templates/quattor';
Readonly::Scalar my $DEFAULT_RELPATH => 'metaconfig';

use base qw(CAF::Object);

use overload ('""' => 'get_text');

=pod

=head1 NAME

CAF::TextRender - Class for rendering structured text 

=head1 SYNOPSIS

    use CAF::TextRender;

    my $module = 'tiny';
    my $rnd = CAF::TextRender->new($module, $contents, log => $self);
    
    print "$rnd"; # stringification

    my $fh = $rnd->fh('/some/path'); # return CAF::FileWriter instance

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
# TODO relative to what?

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

=back

...

=cut

sub _initialize
{
    my ($self, $module, $contents, %opts) = @_;

    %opts = () if !%opts;

    $self->{module} = $module;
    $self->{contents} = $contents;
    
    $self = $opts{log} if $opts{log};

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

    # set render method
    $self->{method} = $self->select_module_method();
    
    return SUCCESS;
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
        $self->error ("Must have a relative template name (got $tplname)");
        return undef;
    }

    if ($tplname !~ m{\.tt$}) {
        $tplname .= ".tt";
    }
    
    # module is relative to relpath
    $tplname = "$self->{relpath}/$tplname" if $self->{relpath};

    $self->debug(3, "We must ensure that all templates lie below $self->{includepath}");
    $tplname = abs_path("$self->{includepath}/$tplname");
    if (!$tplname || !-f $tplname) {
        $self->error ("Non-existing template name $tplname given");
        return undef;
    }

    # untaint and sanitycheck
    # TODO empty relpath will never match
    my $reg = "$self->{includepath}/($self->{relpath}/.*)";
    if ($tplname =~ m{^$reg$}) {
        my $result_template = $1;
        $self->verbose("Using template $result_template for module $self->{module}");
        return $result_template;
    } else {
        $self->error ("Insecure template name $tplname. Final template must be under $self->{includepath}");
        return undef;
    }
}

# Return a Template::Toolkit instance
# (from ncm-ncd Component module)
# Mandatory argument C<includepath> to set the INCLUDE_PATH
sub get_template_instance 
{
    my ($includepath) = @_;
    $Template::Stash::PRIVATE = undef;
    my $template = Template->new(INCLUDE_PATH => $includepath);
    return $template;    
}

# Fallback/default rendering method based on C<Template::Toolkit>. 
# C<module> is a relative path to a TT template.
sub tt 
{
    my ($self) = @_;

    my $sane_tpl = $self->sanitize_template();
    if (!$sane_tpl) {
        $self->error("Invalid template name from module $self->{module}: $sane_tpl");
        return;
    }

    my $tpl = get_template_instance($self->{includepath});

    my $str;
    if (!$tpl->process($sane_tpl, $self->{contents}, \$str)) {
        $self->error("Unable to process template for file $sane_tpl (module $self->{module}: ",
                     $tpl->error());
        return undef;
    }
    return $str;
}

# Return the rendering method corresponding with the C<module>
# If no reserved method name C<render_$module> is found, fallback to 
# C<Template::Toolkit based> C<tt> method is set.
sub select_module_method {

    my ($self) = @_;

    if ($self->{module} !~ m{^([\w+/\.\-]+)$}) {
        $self->error("Invalid configuration module: $self->{module}");
        return;
    }

    my $method;

    if ($method = $self->can("render_".lc($1))) {
        $self->debug(3, "Rendering module $self->{module} with $method");
    } else {
        $method = \&tt;
        $self->debug(3, "Using Template::Toolkit to render module $self->{module}");
    }

    return $method;
}



# Render the text
sub get_text
{
    my ($self) = @_;

    my $res = $self->{method}->($self);

    if (defined($res)) {
        if($self->{eol} && $res !~ m/\n$/) {
            $self->verbose("eol set, and rendered text was missing final newline. adding newline.");
            return $res."\n";
        } else {
            return $res;
        };    
    } else {
        $self->error("Failed to render");
        return;
    }
}

# Create and return an open CAF::FileWriter instance
# C<file> is the filename. Named options C<header> 
# and C<footer> are supported to resp. prepend and append text.
# All other options are passed to CAF::FileWriter. 
# (If no C<log> option is provided, 
# the one from the CAF::TextRender instance is passed).
# The rendered text is added to the filehandle 
# (without extra newline).
# It's up to the consumer to cancel and/or close the instance.
sub fh
{
    my ($self, $file, %opts) = @_;
  
    my $header = delete $opts{header};
    my $footer = delete $opts{footer};
    
    $opts{log} = $self if(!exists($opts{log}));    
    
    my $cfh = CAF::FileWriter->new($file, %opts);
    
    # TODO force newline after header?
    print $cfh $header if defined($header);

    print $cfh $self->get_text();

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
sub load_module
{
    my ($self, $module) = @_;

    $self->verbose("Loading module $module");

    eval "use $module";
    if ($@) {
        $self->error("Unable to load $module: $@");
        return;
    }
    return 1;
}


sub render_json
{
    my ($self) = @_;

    $self->load_module("JSON::XS") or return;
    my $j = JSON::XS->new();
    $j->canonical(1); # sort the keys, to create reproducable results
    return $j->encode($self->{contents});
}


sub render_yaml
{
    my ($self, $cfg) = @_;

    $self->load_module("YAML::XS") or return;

    return YAML::XS::Dump($self->{contents});
}

# Warning: the rendered text has a header with localtime(),
# so the contents will always appear changed.
sub render_properties
{
    my ($self) = @_;

    $self->load_module("Config::Properties") or return;

    my $config = Config::Properties->new(order => 'alpha'); # order results
    $config->setFromTree($self->{contents});
    return $config->saveToString();
}


sub render_tiny
{
    my ($self, $cfg) = @_;

    $self->load_module("Config::Tiny") or return;

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
    my ($self, $cfg) = @_;

    $self->load_module("Config::General") or return;
    my $c = Config::General->new(-SaveSorted => 1); # sort output
    return $c->save_string($self->{contents});
}


1;

