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
use CAF::DummyLogger;

use base qw(CAF::Object);


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

    $self->{method} = $self->select_module_method();
    
    return $self;
}


# Fallback/default rendering method based on C<Template::Toolkit>. 
sub tt 
{
    
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


1;

