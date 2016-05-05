package object_ok;

use strict;
use warnings;

use CAF::Object qw (SUCCESS);

use parent qw(CAF::Object);

sub _initialize {return SUCCESS; };

1;
