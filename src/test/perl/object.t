use strict;
use warnings;

use Test::More;
use Test::MockModule;
use LC::Exception;
# Test the EXPORT_OK
use CAF::Object qw(SUCCESS throw_error);

use FindBin qw($Bin);
use lib "$Bin/modules";

use object_ok;
use object_noaction;
use object_log;
use object_no_initialize;
use object_fail_initialize;

# set it to some odd value for testing purposes
$CAF::Object::NoAction = 5;

my $mockrep = Test::MockModule->new('myreporter');

=pod

=head1 SYNOPSIS

Test all methods for C<CAF::Object>

=over

=item exports

=cut

is(SUCCESS, LC::Exception::SUCCESS, 'CAF::Object exported SUCCESS is LC::Exception::SUCCESS');

=pod

=item new

=cut

my $obj_ok = object_ok->new();
isa_ok($obj_ok, 'object_ok', 'obj_ok is a object_ok');
isa_ok($obj_ok, 'CAF::Object', 'obj_ok is a (subclassed) CAF::Object');
is($obj_ok->{NoAction}, 5, 'CAF::Object new sets NoAction');

my $obj_noaction = object_noaction->new();
isa_ok($obj_noaction, 'object_noaction', 'obj_noaction is a object_noaction');
isa_ok($obj_noaction, 'CAF::Object', 'obj_noaction is a (subclassed) CAF::Object');
is($obj_noaction->{NoAction}, 5, 'CAF::Object new sets NoAction is not defined / undef');

$obj_noaction = object_noaction->new(0);
isa_ok($obj_noaction, 'object_noaction', 'obj_noaction is a object_noaction');
isa_ok($obj_noaction, 'CAF::Object', 'obj_noaction is a (subclassed) CAF::Object');
is($obj_noaction->{NoAction}, 0, 'CAF::Object does not override NoAction if defined');

my $ec = LC::Exception::Context->new()->will_store_errors();
ok(! defined(object_fail_initialize->new()), 'failed _initialize returns undef');
is($ec->error->text(), "cannot instantiate class: object_fail_initialize",
   "error raised with failed subclassed _initialized");
$ec->ignore_error();

ok(! defined(object_no_initialize->new()), 'missing subclassed _initialize returns undef');
is($ec->error->text(),
   "cannot instantiate class: object_no_initialize: *** no constructor _initialize implemented for object_no_initialize",
   "error raised with missing subclassed _initialized");
$ec->ignore_error();

=pod

=item noAction method

=cut

is($obj_ok->noAction(), 5, "noAction method returns NoAction");

=pod

=item conditional loggers

=cut

foreach my $i (qw(error warn info verbose debug report OK event)) {

    my $called = 0;
    # return funny value for testing
    $mockrep->mock($i, sub {$called++; return 2;});

    my $obj_log = object_log->new();
    isa_ok($obj_log, 'object_log', "$i: object_log is a object_log");
    ok(! defined($obj_log->$i()), "$i: conditional logger returns undef if no logger set");
    is($called, 0, "$i: logger method not called");

    my $logger = myreporter->new();
    $obj_log = object_log->new($logger);
    isa_ok($obj_log, 'object_log', "$i with logger: object_log is a object_log");
    is($obj_log->$i(), 2, "$i with logger: conditional logger returns return value of logger if defined");
    is($called, 1, "$i with logger: logger method called");
}

=item fail

=cut

my $verbose;
$mockrep->mock('verbose', sub {shift; $verbose = \@_;});

my $logger = myreporter->new();
my $failobj = object_log->new($logger);
isa_ok($failobj, 'object_log', 'failobj is a object_log instance');

my @failmsg = qw(something went really wrong);
ok(! defined($failobj->fail(@failmsg)), 'fail returns undef');
is($failobj->{fail}, join('', @failmsg), 'fail sets fail attribute with joined arguments');
is_deeply($verbose, ['FAIL: ', $failobj->{fail}], 'fail logs verbose with FAIL prefix');

=item update_env

This does not actually test modifying ENV, only updating a hashref.
For actual testing, see e.g. kerberos-process.t

=cut

# copy ENV (strictly speaking can be any hashref)
my $env = { %ENV };
ok(defined($env->{PATH}), 'PATH defined');

my $varname = 'SOMETHINGRANDOM';
my $varvalue = 'somerandomvalue';
$obj_ok->{ENV}->{PATH} = undef;
$obj_ok->{ENV}->{$varname} = $varvalue;
my $new_env = $obj_ok->update_env($env);

ok(! defined($new_env->{PATH}), 'PATH not defined in updated env');
is($new_env->{$varname}, "$varvalue", "correct $varname set in updated env");

delete $obj_ok->{ENV}->{PATH};


=pod

=back

=cut

done_testing();
