package object_fail_initialize;

use strict;
use warnings;
use LC::Exception qw (SUCCESS);

use parent qw(CAF::Object);

sub _initialize {return 0; };

1;
