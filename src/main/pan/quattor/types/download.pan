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

# similar to kerberos_principal_string in ncm-ccm
# http://web.mit.edu/kerberos/krb5-1.4/krb5-1.4.3/doc/krb5-user/Kerberos-Glossary.html
type kerberos_primary = string with match(SELF, '^\w+$');
type kerberos_realm = string with match(SELF, '^[A-Z][A-Z.-_]*$');
type kerberos_instance = string with match(SELF, '^\w[\w.-]*$');

# TODO: What if you want to use the defaults for all 4 settings?
@documentation{
    CAF::Download kerberos configuration
}
type caf_url_krb5 = {
    'keytab' ? string
    'primary' ? kerberos_primary
    'realm' ? kerberos_realm
    'instances' ? kerberos_instance[]
} with {
    if(exists(SELF['instances']) && ! exists(SELF['primary'])) {
        error("Cannot have krb5 instance(s) without primary");
    };
    true;
};

@documentation{
    CAF::Download X509 configuration
}
type caf_url_x509 = {
    'cacert' ? string
    'capath' ? string
    'cert' ? string
    'key' ? string
} with {
    if(exists(SELF['cacert']) && exists(SELF['capath'])) {
        error('Both X509 cacert and capath defined, cannot have both');
    };
    true;
};

@documentation{
    CAF::Download proxy configuration
}
type caf_url_proxy = {
    'server' : type_hostname
    'port' ? type_port
    'reverse' ? boolean # reverse proxy (default is false, i.e. forward)
};

@documentation{
    CAF::Download supported authentication: one of gssapi, kinit or lwp
}
type caf_url_auth = string with match(SELF, '^(gssapi|kinit|lwp)$');

@documentation{
    CAF::Download supported download method: one of lwp or curl
}
type caf_url_method = string with match(SELF, '^(lwp|curl)$');

@documentation{
    A URL that can be handled by CAF::Download
}
type caf_url = {
    'auth' ? caf_url_auth[]
    'method' ? caf_url_method[]
    'proto' : string with match(SELF, '^(file|https?)$')
    'server' ? type_hostname
    'filename' : string

    #'version' ? string

    'timeout' : long(0..) = 600 # download timeout in seconds (600s * 1kB/s BW = 600kB document)
    'head_timeout' ? long(0..) # timeout in seconds for initial request which checks for changes/existence

    'retries' : long(0..) = 3 # number retries
    'retry_wait' : long(0..) = 30 # number of seconds to wait before a retry

    'krb5' ? caf_url_krb5
    'x509' ? caf_url_x509
    'proxy' ? caf_url_proxy
} with {
    # server is simply ignored with file protocol
    if ((SELF['proto'] != 'file') && (!(exists(SELF['server'])))) {
        error("caf url: cannot set server with file protocol");
    };
    if(exists(SELF['auth'])) {
        foreach(idx; auth; SELF['auth']) {
            if((auth == 'krb5' || auth == 'gssapi') &&
               ! exists(SELF['krb5'])) {
                error(format('Cannot set auth %s without setting krb5', auth));
            };
            if((auth == 'lwp') && ! exists(SELF['x509'])) {
                error('Cannot set auth lwp without setting x509');
            };
        };
    };

    true;
};
