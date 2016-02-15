# ${license-info}
# ${developer-info}
# ${author-info}
# ${build-info}

package CAF::Object;

use strict;
use warnings;

use Exporter;
our @ISA = qw(Exporter);

use LC::Exception qw (SUCCESS throw_error);

our $NoAction;

our @EXPORT = qw();
# For convenience, export most common LC-related constants and methods
our @EXPORT_OK = qw(SUCCESS throw_error);

my $ec = LC::Exception::Context->new()->will_store_all();

=pod

=head1 NAME

CAF::Object - provides basic methods for all CAF objects

=head1 SYNOPSIS

    use parent qw(CAF::Object ...);
    ...
    sub _initialize {
        ... initialize your package
        return SUCCESS; # Success
    }

=head1 DESCRIPTION

B<CAF::Object> is a base class which provides basic functionality to
CAF objects.

All other CAF objects should inherit from it.

All CAF classes use this as their base class and inherit their class
constructor C<new> from here. Sub-classes should implement all their
constructor initialisation in an C<_initialize> method which is invoked
from this base class C<new> constructor. Sub-classes should NOT need to
override the C<new> class method.

The subclass C<_initialize> method has to be implemented
and has to return a boolean value indicating if the initialisation was succesful
(e.g. use C<SUCCESS> exported by C<CAF::Object>).
In particular, one should avoid to return the C<$self> instance at the end of
C<_initialize> (e.g. to avoid troubles when the subclass overloads logic evaluation
(which is also possible via overloading other methods such as stringification)).

=head2 Public methods

=over 4

=item new

Creates an empty hash and bless'es it as the new class instance. All arguments are then passed
to a C<$self->_initialize(@_)> call.
When C<_initialize> returns success, the C<NoAction> attribute is set to the value of
C<CAF::Object::NoAction> if it didn't exist after C<_initialize>.
If C<_initialize> returns failure, an error is thrown and undef returned.

=cut

sub new
{
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
        my $msg = "cannot instantiate class: $class";
        my $err = $ec->error();
        if ($err) {
            $ec->ignore_error();
            $msg .= ": $err";
        }
        throw_error($msg);
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

sub _initialize
{
    my $self = shift;
    throw_error("no constructor _initialize implemented for " . ref($self));
    return;
}

=item error, warn, info, verbose, debug, report, OK

Convenience methods to access the log instance that might
be passed during initialisation and set to $self->{log}.

(When constructing classes via multiple inheritance,
C<CAF::Reporter> should precede C<CAF::Object> if you want
to use an absolute rather than a conditional logger).

=cut

no strict 'refs';
foreach my $i (qw(error warn info verbose debug report OK)) {
    *{$i} = sub {
        my ($self, @args) = @_;
        if ($self->{log}) {
            return $self->{log}->$i(@args);
        } else {
            return;
        }
    }
}
use strict 'refs';


=pod

=item fail

Handle failures. Stores the error message in the C<fail> attribute,
logs it with C<verbose> and returns undef.

To be used in subclasses that are not supposed to log/report
any errors themself when a problem or failure occurs.
In such classes, all failures should use C<return $self->fail("message");>.

=cut

sub fail
{
    my ($self, @messages) = @_;
    $self->{fail} = join('', map {defined($_) ? $_ : '<undef>'} @messages);
    $self->verbose("FAIL: ", $self->{fail});
    return;
}

=pod

=item update_env

Update the hashref C<$env> with key/value
from the C<ENV> attribute hashref.
(A undef value will remove the key.)

Returns the C<env> hashref.

To be used as
    # Setup local environment
    local %ENV;
    $self->update_env(\%ENV);

Example:
    # some method_1 that prepares a shared environment
    sub method_1
    {
        ...
        # Prepare enviroment modifications
        $self->{ENV}->{PATH} = "/some/new/path:$ENV{PATH}";
        ...
    }


    sub do_something
    {
       ...
       # Setup local environment
       local %ENV;
       $self->update_env(\%ENV);

       # everything in the remainder of the method runs in modified environment
       # is limited to the scope of this method due to 'local'
       ...
    }

=cut

sub update_env
{
    my ($self, $env) = @_;

    foreach my $varname (sort keys %{$self->{ENV}}) {
        my $val = $self->{ENV}->{$varname};
        if(defined($val)) {
            $self->debug(1, "update_env $varname = $val.");
            $env->{$varname} = $val;
        } else {
            $self->debug(1, "update_env delete $varname.");
            delete $env->{$varname};
        }
    };

    # For unittesting
    return $env;
}

=pod

=back

=cut

# TODO: these are only send to STDERR, not logged
#       move this to DESTROY?

END {
    # report all stored warnings
    foreach my $warning ($ec->warnings) {
        warn("[WARN] $warning");
    }
    $ec->clear_warnings;
}

1;
