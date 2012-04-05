# Common Application Framework

This is the Perl Common Application Framework (`CAF`) for Quattor.

It is a library encapsulating most annoying details like reporting,
file handling or command executions.

It gives a unified way of doing potentially dangerous things in the
*right* way.

## Applicability

Quattor developers *must* use modules here for:

* Executing commands (see `CAF::Process`).
* Manipulating files (see `CAF::FileWriter` and `CAF::FileEditor`).
* Reporting. Most likely, your code receives a `$self` object that
  provided `CAF`'s interfaces.

## Future notes

This repo contains an outdated version of
[`AppConfig`](http://search.cpan.org/~abw/AppConfig-1.66/lib/AppConfig.pm). There
are RPMs already available for these modules, so we'll stop packaging
it ourselves and rely in what RedHat-derivatives provide.

