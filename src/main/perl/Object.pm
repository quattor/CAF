# ${license-info}
# ${developer-info
# ${author-info}
# ${build-info}
#
#
# CAF::Object class
#

package CAF::Object;

use strict;
our @ISA;
#use CAF::Reporter;
use LC::Exception qw (SUCCESS throw_error);

our $NoAction;

my $ec = LC::Exception::Context->new->will_store_all;

#@ISA = qw(CAF::Reporter);

=pod

=head1 NAME

CAF::Object - provides basic methods for all CAF objects

=head1 SYNOPSIS

  use vars qw (@ISA);
  use LC::Exception qw (SUCCESS throw_error);
  use CAF::Object;
  ...
  @ISA = qw (CAF::Object ...)
  ...
  sub _initialize {
    ... initialize your component
    return SUCCESS; # Success
  }

=head1 INHERITANCE

none.

=head1 DESCRIPTION

B<CAF::Object> is a base class which provides basic functionality to
CAF objects.

All other CAF objects should inherit from it.

All CAF classes use this as their base class and inherit their class
constructor "new" from here. Sub-classes should implement all their
constructor initialisation in an "_initialize" method which is invoked
from this base class "new" constructor. Sub-classes should NOT need to
override the "new" class method.

=over

=cut

#------------------------------------------------------------
#                      Public Methods/Functions
#------------------------------------------------------------

=pod

=back

=head2 Public methods

=over 4

=item new

=cut

sub new {
  my $this = shift;
  my $class = ref($this) || $this;
  my $self = {}; # here, it gives a reference on a hash
  bless $self, $class;
  if ($self->_initialize(@_)) {
    # Initialize instance variable to class variable if not initializedin _initialize().
    # A derived class which must define it differently must define it before.
    $self->{NoAction} = $CAF::Object::NoAction if !defined($self->{NoAction});
    return $self;
  } else {
    throw_error("cannot instantiate class: $class", $ec->error || '');
    undef $self;
    return undef;
  }
}


=item noAction

Returns the NoAction flag value (boolean)

=cut

sub noAction
{
    my $self = shift;
    return $self->{NoAction};
}


=pod

=back

=head2 Private methods

=over 4

=item _initialize

This method must be overwritten in a derived class

=cut

sub _initialize {
  my $self=shift;
  throw_error("no constructor _initialize implemented for ".ref($self));
  return undef;
}

=item error
=item warn
=item info
=item verbose
=item debug

Convenience methods to acess the log instance that might 
be passed during initialisation and set to $self->log.

=cut

no strict 'refs';
foreach my $i (qw(error warn info verbose debug)) {
*{$i} = sub {
            my ($self, @args) = @_;
            return $self->{log}->$i(@args) if $self->{log};
    }
}
use strict 'refs';


=pod

=back

=cut

#------------------------------------------------------------
#                      Other doc
#------------------------------------------------------------

=pod

=head1 SEE ALSO

CAF::Application

=head1 AUTHORS

Ian Neilson, German Cancio

=head1 VERSION

$Id: Object.pm,v 1.4 2008/09/26 14:06:40 poleggi Exp $

=cut


END {
    # report all stored warnings
    foreach my $warning ($ec->warnings) {
        warn("[WARN] $warning");
    }
    $ec->clear_warnings;
}

1; ## END ##
