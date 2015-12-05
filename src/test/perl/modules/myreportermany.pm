package myreportermany;

use strict;
use warnings;

use parent qw(CAF::ReporterMany);

sub new {
    return bless {}, shift;
};

1;
