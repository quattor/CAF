package myreporter;

use strict;
use warnings;

use parent qw(CAF::Reporter);

sub new {
    return bless {}, shift;
};

1;
