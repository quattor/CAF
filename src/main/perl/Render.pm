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

use base qw(CAF::Object);


=pod

=head1 NAME

CAF::Render - Class for rendering structured text 

=head1 SYNOPSIS

    use CAF::Render;

    my $module = 'tiny';
    my $rnd = CAF::Render->new($module, $data, log => $self);
    
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

=item C<$data>

C<data> is a hash reference holding the data to pass to the rendering module.

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
    my ($self, $module, $data, %opts) = @_;

    %opts = () if !%opts;

    $self->{_module} = $module;
    $self->{_data} = $data;

    if (exists $opts{log}) {
        if ($opts{log}) {
            $self->{log} = $opts{log};
        }
    }

    return $self;
}


1;

