use strict;
use warnings;

use Test::More;

# needs real LC for CCM, not the mocked one set via -I in pom.xml
BEGIN {
    @INC = grep {$_ !~ /CAF\/src\/test\/resources/ } @INC;
};
use Test::Quattor qw(download_pan);

# would have failed on import otherwsie
ok(1, "Compilation of pan template with caf_url schema check ok");

done_testing();
