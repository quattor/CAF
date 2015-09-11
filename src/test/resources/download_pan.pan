object template download_pan;

include 'quattor/types/download';

"/strings" = list(
    "http://www.something.com/whatever",
    "https://www.something.com/whatever",
    "file:///my/path",
    "gssapi+lwp+https://my.server/location",
    "x509+curl+https://my.server/location",
    "kinit+curl+https://my.server/location",
    "kinit+lwp+file:///some/otherfile",
);

bind "/strings" = caf_url_string[];
