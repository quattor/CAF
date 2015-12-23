use strict;
use warnings;

BEGIN {
    # remove the module path that is holding the temp LC mock
    # we actually want to run something here
    @INC = grep { $_ !~ m/resources$/ } @INC;
}

use CAF::Kerberos;
use Test::More;

use Test::Quattor::Object;

my $obj = Test::Quattor::Object->new();

my $krb = CAF::Kerberos->new(log => $obj);
isa_ok($krb, 'CAF::Kerberos', 'returns a CAF::Kerberos instance');

=item _process

=cut

my $unique_var = "SOMETHINGUNIQUE";
my $unique_value = "somethingunique";

ok(! defined($ENV{$unique_var}), "$unique_var not defined in environment");
$krb->{ENV}->{$unique_var} = $unique_value;
my $output = $krb->_process(['bash', '-c', "echo \$$unique_var"]);
is($output, "$unique_value\n", "_process runs in merged environment");
ok(! defined($ENV{$unique_var}), "$unique_var not defined in environment after run");

done_testing();
