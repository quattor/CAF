declaration template quattor/types/download;

include 'pan/types';

@documentation{
    A string that represents a URL that can be handled by CAF::Download
    Format: [auth+][method+]protocol://location
    Protocols: http|file
    Methods: lwp|curl transport
    Auth: kinit|gssapi|x509 authentication
    Location: anything
}
type caf_url_string = string with {
    mp_l = split('://', SELF);

    if (length(mp_l) != 2) {
        error('invalid URL string requires ://, got' + SELF);
        return(false);
    };

    if(! match(mp_l[0], '^((kinit|gssapi|x509)\+)?((lwp|curl)\+)?(https?|file)$')) {
        error('invalid method+protocol for ' + mp_l[0]);
        return(false);
    };

    a_m_p = split('\+', mp_l[0]);
    protocol = a_m_p[length(a_m_p)-1];

    if (protocol == 'file' && (!match(mp_l[1], '^/'))) {
        error("location for file protocol has to start with /, got " + mp_l[1]);
        return(false);
    };

    true;
};

@documentation{
    A URL that can be handled by CAF::Download
}
type caf_url = {
};
