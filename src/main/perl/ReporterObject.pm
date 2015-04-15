# ${license-info}
# ${developer-info}
# ${author-info}
# ${build-info}

package CAF::ReporterObject;

use strict;
use vars qw(@ISA $_SINGLETON);
use CAF::Object;
use LC::Exception qw (SUCCESS throw_error);
use CAF::Reporter;

@ISA = qw(CAF::Reporter CAF::Object);


BEGIN {
  # ensure no object defined on startup
  $_SINGLETON=undef;
}

=pod

=head1 NAME

CAF::ReporterObject - singleton Reporter object class

=head1 SYNOPSIS

 use CAF::ReporterObject;
 my $r=CAF::ReporterObject->instance();

 $r->report("whatever");
 $r->debug("blah blah");
 ...

=head1 INHERITANCE

  CAF::Reporter
  CAF::Object

=head1 DESCRIPTION

Provides a wrapper class to instantiate the Reporter as a singleton object.

=over

=cut

#------------------------------------------------------------
#                      Public Methods/Functions
#------------------------------------------------------------

=pod

=back

=head2 Public methods

=over 4

=item instance(): ReporterObject

returns the ReporterObject instance and creates it if
neccessary. ReporterObject is a singleton.

=cut


sub instance () {
  my $class=shift;

  return $_SINGLETON
    if (defined $_SINGLETON);
  $_SINGLETON=$class->SUPER::new();
  return $_SINGLETON;
}

=pod

=item new(): throws error

new() throws an error, as this method is not to be used (instead,
create/get the singleton with instance())

=back

=cut

sub new () {
  throw_error("new() cannot be used for ReporterObject singleton class");
  return ();
}


=head2 Private methods

=over 4

=item _initialize()

initialize the singleton.

=cut

sub _initialize () {
  return SUCCESS;
}

=pod

=back

=cut

#------------------------------------------------------------
#                      Other doc
#------------------------------------------------------------

=pod

=head1 SEE ALSO

CAF::Object, LC::Exception, CAF::Reporter

=cut

1; ## END ##
