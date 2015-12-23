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

"/kerberos_primaries" = list(
    'username',
);

bind "/kerberos_primaries" = kerberos_primary[];

"/kerberos_realms" = list(
    'MY.REALM',
);

bind "/kerberos_realms" = kerberos_realm[];

"/kerberos_instances" = list(
    'a.component',
    'something.else',
    'my.hostname',
);

bind "/kerberos_instances" = kerberos_instance[];

"/krb5s" = list(
    dict(
        'keytab', '/some/file',
        'primary', 'myuser',
        'realm', 'MY.REALM',
        'instances', list('test1', 'other.host'),
    ),
);

bind "/krb5s" = caf_url_krb5[];

"/x509s" = list(
    dict(
        'cacert', '/some/file',
        'cert', '/my/cert',
        'key', '/my/key',
    ),
    dict(
        'capath', '/some/dir',
        'cert', '/my/cert',
        'key', '/my/key',
    ),
);

bind "/x509s" = caf_url_x509[];

"/proxys" = list(
    dict(
        'server', 'my.proxyhost',
    ),
    dict(
        'server', 'my.rev.proxyhost',
        'port', 8765,
        'reverse', true,
    ),
);

bind "/proxys" = caf_url_proxy[];

"/auths" = list(
    'gssapi',
    'kinit',
    'lwp',
);

bind "/auths" = caf_url_auth[];

"/methods" = list(
    'lwp',
    'curl',
);

bind "/methods" = caf_url_method[];

"/urls" = list(
    dict(
        'auth', list('gssapi','kinit'),
        'method', list('curl'),
        'proto', 'https',
        'server', 'my.server',
        'filename', '/location/on/server',
        'timeout', 30,
        'head_timeout', 50,
        'retries', 10,
        'retry_wait', 30,
        'krb5', dict(
            'primary', 'me',
        ),
        'proxy', dict(
            'server', 'myforward',
        ),
    ),
);

bind "/urls" = caf_url[];
