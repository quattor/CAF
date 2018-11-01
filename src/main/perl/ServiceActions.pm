#${PMpre} CAF::ServiceActions${PMpost}

use parent qw(CAF::Object Exporter);
use CAF::Service;
use CAF::Object qw(SUCCESS);

use Readonly;

# to keepin sync with caf_service_actions type in template-library-core quattor/types/component
Readonly our @SERVICE_ACTIONS => qw(restart reload stop_sleep_start);

our @EXPORT_OK = qw(@SERVICE_ACTIONS);

=pod

=head1 NAME

CAF::ServiceActions - Class for running different C<CAF::Service> actions
on groups of daemons.

=head1 SYNOPSIS

    use CAF::ServiceActions;

    # short
    CAF::ServiceActions->new(log => $self, pairs => {daemon1 => 'start', 'daemon2' => 'reload'})->run();

    # long
    my $srvact = CAF::ServiceActions->new(log => $self);
    ...
    $srvact->add({daemon1 => 'restart', daemon2 => 'reload'});
    ...
    $srvact->add({daemon3 => 'restart'}, msg => 'for file XYZ');
    ...
    $srvact->run();


=head1 DESCRIPTION

This class can be used to run different C<CAF::Service> actions
on groups of daemons.

=cut

=head2 Private methods

=over

=item C<_initialize>

Initialize the object.
It takes optional arguments:

=over

=item C<log>

A C<CAF::Reporter> object to log daemon activities to.

=item C<pairs>

Daemon/action pairs (in hashref) passed to C<add> method.

=back

All other named options are passed to C<add> method if the C<pairs> option is passed.

=cut

sub _initialize
{
    my ($self, %opts) = @_;

    $self->{log} = delete $opts{log};

    $self->{actions} = {};

    my $pairs = delete $opts{pairs};
    if ($pairs) {
        $self->add($pairs, %opts);
    };

    return SUCCESS;
}

=item C<add>

Add daemon/action C<pairs> as hashref, e.g.

    $srvact->add({daemon1 => 'restart', daemon2 => 'stop'});

Does not run any service action (see C<run> method).

It takes optional arguments:

=over

=item C<msg>

A string that is appended to the log messages.

=back

Returns SUCCESS on success, undef otherwise.

=cut

sub add
{
    my ($self, $pairs, %opts) = @_;

    my $msg = $opts{msg} || '';
    $msg = " $msg" if $msg;

    my @acts;
    foreach my $daemon (sort keys %{$pairs || {}}) {
        my $action = $pairs->{$daemon};
        if (grep {$_ eq $action} @SERVICE_ACTIONS) {
            $self->{actions}->{$action} ||= {};
            $self->{actions}->{$action}->{$daemon} = 1;
            push(@acts, "$daemon:$action");
        } else {
            $self->error("Not a CAF::ServiceActions allowed action ",
                         "$action for daemon $daemon ",
                         "(allowed actions are ",
                         join(',', @SERVICE_ACTIONS), ")$msg");
        }
    }

    if (@acts) {
        $self->verbose("Scheduled daemon/action ".join(', ',@acts).$msg);
    } else {
        $self->verbose("No daemon/action scheduled$msg");
    }

    return SUCCESS
}

=item C<run>

Run the actions for all daemons.

=cut

sub run
{
    my $self = shift;

    my @actions = sort keys %{$self->{actions}};
    if (@actions) {
        foreach my $action (@actions) {
            my @daemons = sort keys %{$self->{actions}->{$action}};
            $self->info("Executing action $action on services: ", join(',', @daemons));
            my $srv = CAF::Service->new(\@daemons, log => $self);
            # CAF::Service does all the logging we need
            $srv->$action();
        }
    } else {
        $self->verbose("No scheduled actions for any services");
    }
}

=pod

=back

=cut

1;
