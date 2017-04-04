# hopscotch

hopscotch is a tiny, high-performance HTTP image proxy. The idea is that you
put it behind your SSL terminator. When you serve user content you rewrite
image URLs to point to it. Just like that, all the assets in the page are
served over SSL and you avoid mixed content warnings.

It's inspired by [Camo](https://github.com/atmos/camo), Github's implementation
of the same concept.

## features

- returns 404 for all errors
- cache friendly
- transparently follow redirects
- limit content by size or MIME type
- paranoid mode that fails requests to internal networks

## setup

### docker

```bash
$ docker run --name hopscotch.psgi -e HOPSCOTCH_KEY=abc123 -d -p 8080:8080 bin/hopscotch.psgi
```

### carton

```bash
$ git clone http://github.com/fastmail/hopscotch.git
$ cd hopscotch
$ curl -L http://cpanmin.us | perl - Carton Starlet
$ carton install --deployment
$ env HOPSCOTCH_KEY=abc123 carton exec plackup -s Starlet -p 8080 ./bin/hopscotch.psgi
```

### anything else

Get Perl, get all the dependencies, run the program. This is the developer
option, and you're expected to know what you're doing :)

## URL format

hopscotch URLs look like:

    http://hopscotch/<digest>/<hexurl>

`<digest>` is the SHA256 HMAC digest generated from the unescaped image URL and
a secret key that you provide. `hexurl` is a simple hex encoding (two hex
digits per string byte, lowercase) of the same image URL used to generate the
digest.

Sample Perl code to generate a URL:

```perl
use Crypt::Mac::HMAC qw(hmac_hex);
my $hsurl = "http://hopscotch:8080/" . hmac_hex("SHA256", $KEY, $URL) . "/" . unpack("h*", $URL);
```

## config

hopscotch is configured with environment variables.

* `HOPSCOTCH_KEY`: shared key used to generate the HMAC digest (required)
* `HOPSCOTCH_HOST`: name to insert in the `x-hopscotch-host` header returned to
                    clients (default: `unknown`)
* `HOPSCOTCH_TIMEOUT`: max seconds hopscotch will wait for a response befores
                       giving up (default: 10)
* `HOPSCOTCH_HEADER_VIA`: string to include in the `via` header set to the
                          origin host (default: `hopscotch`)
* `HOPSCOTCH_HEADER_UA`: string to include in the `user-agent` header set to the
                         origin host (default: `hopscotch`)
* `HOPSCOTCH_LENGTH_LIMIT`: maximum `content-length` hopscotch will proxy (default:
                            5242880)
* `HOPSCOTCH_MAX_REDIRECTS`: maximum number of redirect hopscotch will follow
                             (default: 4)
* `HOPSCOTCH_PARANOID`: if set to a true value, hopscotch will refuse to connect
                        to "internal" networks as determined by
                        [`Net::DNS::Paranoid`](https://metacpan.org/pod/Net::DNS::Paranoid).
                        This costs an extra DNS lookup for each request but
                        protects against a class of SSRF attacks (default: 0)
* `HOPSCOTCH_ERRORS`: if set to a true value, reasons for proxy failures will
                      be output to stderr (default: true)
* `HOPSCOTCH_CAFILE`: file containing CA certificates for HTTPS verification (default: unset)
* `HOPSCOTCH_CAPATH`: dir containing CA certificates for HTTPS verification (default: unset)

If neither the `CAFILE` nor the `CAPATH`, the certificates provided by
`Mozilla::CA` will be used.

## who's using this?

* [FastMail](https://www.fastmail.fm/) are using this to serve images embedded in email

## credits and license

Copyright (c) 2014 Robert Norris. MIT license. See [LICENSE.md](LICENSE.md)

## contributing

Please hack on this and send pull requests :)

