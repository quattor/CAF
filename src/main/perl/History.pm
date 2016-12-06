#${PMpre} CAF::History${PMpost}

use LC::Exception qw (SUCCESS);
use Readonly;

use parent qw(Exporter);
our @EXPORT_OK = qw($EVENTS $IDX $ID $TS $REF);

# refaddr was added between 5.8.0 and 5.8.8
use 5.8.8;
use Scalar::Util qw(blessed refaddr);

# This might become problematic when dealing with global destroy
# And we should, since destroying instances held in history might
# trigger more events

Readonly our $EVENTS => 'EVENTS';
Readonly my $LAST => 'LAST';
Readonly my $NEXTIDX => 'NEXTIDX';
Readonly my $INSTANCES => 'INSTANCES';

Readonly our $IDX => 'IDX';
Readonly our $ID => 'ID';
Readonly our $TS => 'TS';
Readonly our $REF => 'REF';


# DESTROY issues with Readonly
my $_EVENTS = $EVENTS;
my $_INSTANCES = $INSTANCES;

# The 'why' part:
# Initial work was implemented via the add_files method in ncm-ncd
# coupled to CAF::FileWriter close.
# However, we need more metadata of e.g. CAF operations to be able to
#   - not remove files accessed by CAF::FileReader (which is a FileWriter close)
#   - not remove files accessed by CAF::FileWriter that were never modified
#   - restore backups on removal (if backup available? with what name/extension?)
#       - but how do we now if the backup is the original?
#   - restore original symlink if symlink existed before?
#   - ...
# Some of these cases might be handled by precise usage of event logging
# (e.g. only add_files when close actually modifies), but might be limiting
# in functionality.
# This class allows to simply (there's only '->event()')
# track a lot more, and decide on what to do later.
# It might also be used for auditing CAF
# (e.g. what access which file, what calls which process).

=pod

=head1 NAME

C<CAF::History> - Class to keep history of events

=head1 SYNOPSIS

    package mypackage;

    use qw(CAF::History);

    sub _initialize
    {
        ...
        $self->{HISTORY} = CAF::History->new();
        ...
    }

    sub foo {
        my ($self, $a, $b, $c) = @_;
        ...
        $self->{HISTORY}->event();
        ...
    }

=head1 DESCRIPTION

C<CAF::History> provides class methods for tracking and
lookup of events.

TODO: C<CAF::History> should provide interfaces for

=over

=item loading / saving history to file e.g. sqlite

=item lookup / querying events (e.g. what files where
last written to by component X)

=back

=head2 Public methods

=over

=item new

Create a C<CAF::History> instance,

The history is a hashref with keys

=over

=item C<$EVENTS>

an array reference holding all events.

=item C<$LAST>

The latest state of each id

=item C<$NEXTIDX>

The index of the next event.

=item optional C<$INSTANCES>

If C<keep_instances> is set, an INSTANCES attribute is also added,
and any events will keep track of the (blessed) instances.

Caveat: this will prevent code that relies on instances going out
of scope to perform certain actions on DESTROY, to function properly.

By default, INSTANCES are not kept.

=back

=cut

sub new
{
    my ($this, $keep_instances, $nextidx) = @_;

    my $class = ref($this) || $this;
    my $self = {}; # here, it gives a reference on a hash

    $self->{$EVENTS} = [];
    $self->{$LAST} = {};
    $self->{$NEXTIDX} = $nextidx || 0;

    $self->{$INSTANCES} = {} if $keep_instances;

    bless $self, $class;

    return $self;
}

=pod

=item event

Add an event. An event is specified by an id from the C<$obj>
and a hash C<metadata>. (Metadata can be passed as
C<<->event($obj, modified => 0);>>.)

If an instance is passed, the C<Scalar::Util::refaddr> is used as internal
identifier. If a scalar is passed, it's value is used.

Object instances are also added to an instances hash-ref to handle DESTROY properly
(but only if the initial HISTORY attribute has an INSTANCES attribute).

Following metadata is added automatically

=over

=item C<IDX>

The unique event index, increases one per event.

=item C<ID>

The identifier

=item C<REF>

The obj C<ref>

=item C<TS>

The timestamp (private method C<_now> is used to determine the timestamp)

=back

The last metadata of each event is also held stored (for convenient access).

Returns SUCCESS on success, undef otherwise.

=cut

# We cannot hold instances as keys, e.g. when stringification is implemented.

sub event
{
    my ($self, $obj, %metadata) = @_;

    my $ref = ref($obj);
    my $id = "$ref "; # add space as separator

    if($ref) {
        $id .= refaddr($obj);
        $self->{$INSTANCES}->{$id} = $obj
            if(blessed($obj) && defined($self->{$INSTANCES}));
    } else {
        $id .= $obj;
    }

    $metadata{$IDX} = $self->{$NEXTIDX}++;
    $metadata{$ID} = $id;
    $metadata{$REF} = $ref;
    $metadata{$TS} = $self->_now();

    push(@{$self->{$EVENTS}}, \%metadata);
    $self->{$LAST}->{$id} = \%metadata;

    return SUCCESS;
}

=pod

=item query_raw

Primitive interface to query the events.

C<match> is a anonymous sub that is passed
the event as (only) argument
(each event is a metadata hashref).
Returns true if the event matches and is to be returned.

C<filter> is an arrayref of metadata keys to filter from the event
(only event metadata matching the filter is returned).

Returns an arrayref of (a shallow copy of) the event metadata.

TODO: support proper, human-friendly query interface via (NO)SQL

=cut

sub query_raw
{
    my ($self, $match, $filter) = @_;

    my @res;
    foreach my $ev (@{$self->{$EVENTS}}) {
        if ($match->($ev)) {
            my $res_ev;
            if($filter) {
                # only add existing attributes, otherwise a hashslice would be better
                my %f_ev = map { $_ => $ev->{$_} } grep { exists $ev->{$_} } @$filter;
                $res_ev = \%f_ev;
            } else {
                # shallow copy
                $res_ev = { %$ev };
            }
            push(@res, $res_ev);
        }
    }

    return \@res;
}


=pod

=item close

Closes the history which triggers following

=over

=item destroy INSTANCES

=item TODO: report an overview of events

E.g. all modified FileWriter and Editors

=back

Returns SUCCESS on success, undef otherwise.

=cut

# Need non-Readonly key names here.

sub close
{
    my ($self) = @_;

    return SUCCESS if (! defined($self->{$_EVENTS}));

    # Destroy any leftover instances first. This might cause other events.
    $self->_cleanup_instances();

    $self->{$_EVENTS} = undef;

    return SUCCESS;
}

=pod

=back

=head2 Private methods

=over

=item _now

Return the timestamp to use. Implemented using builtin C<time> for now,
i.e. no timezones.

=cut

sub _now
{
    my ($self) = @_;
    return time();
}

=pod

=item _cleanup_instances

Cleanup instances and remove any reference
to instances held by the history.

This might trigger new events.
After all, we must make sure we have all the events.

Following methods are supported

=over

=item C<close>

If the instance has a C<close> method, the method is
called without any arguments.

=back

Returns SUCCESS on success, undef otherwise.

=cut

# This can trigger exceptions and stuff

sub _cleanup_instances
{
    my ($self) = @_;

    my $instances = $self->{$_INSTANCES};

    return SUCCESS if(! defined($instances));

    foreach my $id (keys(%$instances)) {
        my $obj = $instances->{$id};

        # Supported destroy methods
        $obj->close() if $obj->can('close');

        # remove (any) reference to the instance held here
        $obj = undef;
        $instances->{$id} = undef;
    }

    # Events triggered above might re-add the instances.
    # Clean it up completely
    $self->{$_INSTANCES} = undef;

    return SUCCESS;
}

=pod

=back

=cut

# All Readonly (and in methods called) might be
# cleaned up during global cleanup, so use the $_XYZ
# flavours here (and methods called here).
sub DESTROY {
    my $self = shift;
    $self->close() if defined($self->{$_EVENTS});
}


1;
