# ${license-info}
# ${developer-info
# ${author-info}
# ${build-info}
#
#
# CAF::Render class

package CAF::Render;

use strict;
use warnings;
use LC::Exception qw (SUCCESS);
use CAF::DummyLogger;
use CAF::FileWriter;
use Cwd qw(abs_path);
use File::Spec::Functions qw(file_name_is_absolute);
use Template;
use Template::Stash;

use Readonly;

Readonly::Scalar my $DEFAULT_TEMPLATE_BASE => '/usr/share/templates/quattor';
Readonly::Scalar my $DEFAULT_RELPATH => 'metaconfig';

use base qw(CAF::Object);

use overload ('""' => 'get_text');

=pod

=head1 NAME

CAF::Render - Class for rendering structured text 

=head1 SYNOPSIS

    use CAF::Render;

    my $module = 'tiny';
    my $rnd = CAF::Render->new($module, $contents, log => $self);
    
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

=item C<$module>

The rendering module to use: either one of the following reserved values 
C<json> (using C<JSON::XS>), 
C<yaml> (using C<YAML::XS>), 
C<properties> (using C<Config::Properties>), 
C<tiny> (using C<Config::Tiny>),
C<general> (using C<Config::General>)

Or, for any other value, C<Template::Toolkit> is used, and the C<module> then indicates 
the relative path of the template to use.
# TODO relative to what?

=item C<$contents>

C<contents> is a hash reference holding the contents to pass to the rendering module.

=back

It takes some extra optional arguments:

=over

=item C<log>

A C<CAF::Reporter> object to log to.

=item C<templatebase>

The basedirectory for TT template files, and the INCLUDEPATH 
for the Template instance.

=item C<relpath>

The relative path w.r.t. the templatebase to look for TT template files.
This relative path should not be part of the module name, however it 
is not the INCLUDEPATH. (In particular, any TT C<INCLUDE> statement has 
to use it as the relative basepath).

=back

...

=cut

sub _initialize
{
    my ($self, $module, $contents, %opts) = @_;

    %opts = () if !%opts;

    $self->{module} = $module;
    $self->{contents} = $contents;
    
    if (exists $opts{log} && $opts{log}) {
        $self->{log} = $opts{log};
    } else {
        $self->{log} = CAF::DummyLogger->new();
    }

    if (exists $opts{templatebase}) {
        $self->{templatebase} = $opts{templatebase};
    } else {
        $self->{templatebase} = $DEFAULT_TEMPLATE_BASE;
    }
    $self->{log}->verbose("Using templatebase $self->{templatebase}");
    
    if (exists $opts{relpath}) {
        $self->{relpath} = $opts{relpath};
    } else {
        $self->{relpath} = $DEFAULT_RELPATH;
    }
    $self->{log}->verbose("Using relpath $self->{relpath}");

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
        $self->{log}->error ("Must have a relative template name (got $tplname)");
        return undef;
    }

    if ($tplname !~ m{\.tt$}) {
        $tplname .= ".tt";
    }
    
    # module is relative to relpath
    $tplname = "$self->{relpath}/$tplname" if $self->{relpath};

    $self->{log}->debug(3, "We must ensure that all templates lie below $self->{templatebase}");
    $tplname = abs_path("$self->{templatebase}/$tplname");
    if (!$tplname || !-f $tplname) {
        $self->{log}->error ("Non-existing template name $tplname given");
        return undef;
    }

    # untaint and sanitycheck
    # TODO empty relpath will never match
    my $reg = "$self->{templatebase}/($self->{relpath}/.*)";
    if ($tplname =~ m{^$reg$}) {
        my $result_template = $1;
        $self->{log}->verbose("Using template $result_template for module $self->{module}");
        return $result_template;
    } else {
        $self->{log}->error ("Insecure template name $tplname. Final template must be under $self->{templatebase}");
        return undef;
    }
}

# Return a Template::Toolkit instance
# (from ncm-ncd Component module)
sub get_template_instance 
{
    my ($self) = @_;
    $Template::Stash::PRIVATE = undef;
    my $template = Template->new(INCLUDE_PATH => $self->{templatebase});
    return $template;    
}

# Fallback/default rendering method based on C<Template::Toolkit>. 
# C<module> is a relative path to a TT template.
sub tt 
{
    my ($self) = @_;

    my $sane_tpl = $self->sanitize_template();
    if (!$sane_tpl) {
        $self->{log}->error("Invalid template name from module $self->{module}: $sane_tpl");
        return;
    }

    my $tpl = $self->get_template_instance();

    my $str;
    if (!$tpl->process($sane_tpl, $self->{contents}, \$str)) {
        $self->{log}->error("Unable to process template for file $sane_tpl (module $self->{module}: ",
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
        $self->{log}->error("Invalid configuration module: $self->{module}");
        return;
    }

    my $method;

    if ($method = $self->can("render_".lc($1))) {
        $self->{log}->debug(3, "Rendering module $self->{module} with $method");
    } else {
        $method = \&tt;
        $self->{log}->debug(3, "Using Template::Toolkit to render module $self->{module}");
    }

    return $method;
}

# Render the text
sub get_text
{
    my ($self) = @_;

    my $res = $self->{method}->($self);

    if (defined($res)) {
        return $res;
    } else {
        $self->{log}->error("Failed to render");
        return;
    }
}

# Create and return a CAF::FileWriter instance
# C<file> is the filename, C<%opts> are passed to 
# CAF::FileWriter. (If no C<log> option is provided, 
# the one from the CAF::Render instance is passed).
# The rendered text is added to the filehandle 
# (without extra newline).
sub fh
{
    my ($self, $file, %opts) = @_;
    
    $opts{log} = $self->{log} if(!exists($opts{log}));    
    
    my $cfh = CAF::FileWriter->new($file, %opts);
    
    print $cfh $self->get_text();

    return $cfh
}


1;

