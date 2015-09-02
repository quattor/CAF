package object_ok;

use strict;
use warnings;
use LC::Exception qw (SUCCESS);

use parent qw(CAF::Object);

sub _initialize {return SUCCESS; };

1;
