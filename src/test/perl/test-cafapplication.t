use strict;
use warnings;
use Test::More;

use Test::MockModule;
use CAF::Application qw($OPTION_CFGFILE);


is($OPTION_CFGFILE, 'cfgfile',
   "Magic configfile option name $OPTION_CFGFILE");

# test predefined options
my $defapp = CAF::Application->new('mydefname');
isa_ok($defapp, 'CAF::Application', 'A CAF::Application instance');
is($defapp->{NAME}, 'mydefname', 'NAME attribute set');

ok(! defined($defapp->option($OPTION_CFGFILE)), "OPTION_CFGFILE is undef by default");

# mock an application
my $def_cfgfile = '/doesnotexist/apptest.cfg';
my $def_value = 'mydefault';

my $mock = Test::MockModule->new('CAF::Application');
$mock->mock('app_options', sub {
    return [
        {
            NAME => "$OPTION_CFGFILE=s",
            DEFAULT => $def_cfgfile,
            HELP => 'Config file for test app',
        },
        {
            NAME => 'myoption=s',
            DEFAULT => $def_value,
            HELP => 'A very useful option',
        },
        ];
});

my $app = CAF::Application->new('myname');
isa_ok($app, 'CAF::Application', 'A CAF::Application instance');
is($app->{NAME}, 'myname', 'NAME attribute set');

# pick up the default
ok(! -f $def_cfgfile, "No default configfile $def_cfgfile found");
is($app->option($OPTION_CFGFILE), $def_cfgfile,
   "Default config file location $def_cfgfile");
is($app->option('myoption'), $def_value,
   "Default myoption value");

# use actual cfgfile
my $cfgfile = 'src/test/resources/apptest.cfg';
my $value = 'myvalue';

# 1st format --cfgile path/tofile
my $newapp = CAF::Application->new('myname', "--$OPTION_CFGFILE", $cfgfile);
isa_ok($newapp, 'CAF::Application', 'A CAF::Application instance');

ok(-f $cfgfile, "configfile $cfgfile found");
is($newapp->option($OPTION_CFGFILE), $cfgfile,
   "Specified config file location $cfgfile via --cfgile path/tofile");
is($newapp->option('myoption'), $value,
   "myoption value from configfile");

# 2nd format --cfgile=path/tofile
my $newapp2 = CAF::Application->new('myname', "--$OPTION_CFGFILE=$cfgfile");
isa_ok($newapp2, 'CAF::Application', 'A CAF::Application instance');

is($newapp2->option($OPTION_CFGFILE), $cfgfile,
   "Specified config file location $cfgfile --cfgile=path/tofile");
is($newapp2->option('myoption'), $value,
   "myoption value from configfile (2nd format)");


done_testing();
