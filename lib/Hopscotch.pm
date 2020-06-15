use 5.010;
use strict;
use warnings;
package Hopscotch;
# ABSTRACT: tiny, high-performance HTTP image proxy

use Furl::HTTP;
use List::MoreUtils qw(natatime);
use Try::Tiny;
use File::LibMagic 1.02;
use Hash::MultiValue;

use constant HOST          => $ENV{HOPSCOTCH_HOST}          // "unknown";
use constant TIMEOUT       => $ENV{HOPSCOTCH_TIMEOUT}       // 60;
use constant HEADER_VIA    => $ENV{HOPSCOTCH_HEADER_VIA}    // "1.0 hopscotch";
use constant HEADER_UA     => $ENV{HOPSCOTCH_HEADER_UA}     // "hopscotch";
use constant LENGTH_LIMIT  => $ENV{HOPSCOTCH_LENGTH_LIMIT}  // 5242880;
use constant MAX_REDIRECTS => $ENV{HOPSCOTCH_MAX_REDIRECTS} // 4;
use constant PARANOID      => $ENV{HOPSCOTCH_PARANOID}      // 0;
use constant ERRORS        => $ENV{HOPSCOTCH_ERRORS}        // 1;
use constant CAFILE        => $ENV{HOPSCOTCH_CAFILE}        // undef;
use constant CAPATH        => $ENV{HOPSCOTCH_CAPATH}        // undef;
use constant IGNORE_CERTS  => $ENV{HOPSCOTCH_IGNORE_CERTS}  // undef;
use constant NO_WARN       => $ENV{HOPSCOTCH_NO_WARN}       // undef;

my %COPY_REQUEST_HEADERS = map { $_ => 1 } qw(
    accept accept-language cache-control if-modified-since if-match if-none-match if-unmodified-since
);

my %COPY_RESPONSE_HEADERS = map { $_ => 1 } qw(
    content-type cache-control etag expires last-modified content-length server
);

my %VALID_CONTENT_TYPES = map { $_ => 1 } qw(
    image/bmp
    image/bitmap
    image/cgm
    image/g3fax
    image/gif
    image/ief
    image/jp2
    image/jpg
    image/jpeg
    image/pict
    image/png
    image/prs.btif
    image/svg+xml
    image/tiff
    image/webp
    image/vnd.adobe.photoshop
    image/vnd.djvu
    image/vnd.dwg
    image/vnd.dxf
    image/vnd.fastbidsheet
    image/vnd.fpx
    image/vnd.fst
    image/vnd.fujixerox.edmics-mmr
    image/vnd.fujixerox.edmics-rlc
    image/vnd.microsoft.icon
    image/vnd.ms-modi
    image/vnd.net-fpx
    image/vnd.wap.wbmp
    image/vnd.xiff
    image/x-cmu-raster
    image/x-cmx
    image/x-macpaint
    image/x-pcx
    image/x-pict
    image/x-portable-anymap
    image/x-portable-bitmap
    image/x-portable-graymap
    image/x-portable-pixmap
    image/x-quicktime
    image/x-rgb
    image/x-xbitmap
    image/x-xpixmap
    image/x-xwindowdump
);

sub request_headers {
    my ($headers) = @_;
    my $it = natatime 2, @$headers;
    [
        (map { my ($k, $v) = $it->(); exists $COPY_REQUEST_HEADERS{lc($k)} ? (lc($k), $v) : () } (1..(scalar @$headers)/2)),
        'Via' => HEADER_VIA,
        'Accept-encoding' => 'identity',
    ];
}

sub response_headers {
    my ($headers) = @_;
    my $it = natatime 2, @$headers;
    my @out_headers;

    while (my ($k, $v) =  $it->()) {
        next unless exists $COPY_RESPONSE_HEADERS{ lc $k };

        # Chosen arbitrarily as "seems pretty large". -- rjbs, 2020-06-15
        if (length $v > 1024 && ! NO_WARN) {
            warn sprintf "proxying large (%ib) %s header", length $v, $k;
        }

        push @out_headers, lc $k, $v;
    }

    push @out_headers, (
        'Via' => HEADER_VIA,
        'X-Hopscotch-Host' => HOST,
    );

    return \@out_headers;
}

sub cleanup_error {
    return unless ERRORS;
    my ($err) = @_;
    $err =~ s/ at .+ line.*//sm;
    "E: $err\n";
}

sub response {
    my $err;
    if (defined $_[2]) {
        $err = cleanup_error($_[2]) if defined $_[2];
        warn $err unless NO_WARN;
        $_[1] //= [];
        push @{$_[1]}, 'Content-type' => 'text/plain';
    }
    [ $_[0], response_headers($_[1] // []), [ $err // () ] ];
}

my %header_checks = (
    "content-length" => sub { 0+$_[0] <= LENGTH_LIMIT },
);

sub rejected {
    my ($code, $msg, $headers) = @_;

    {
        my $codetype = substr $code, 0, 1;
        return (1, "remote returned $code $msg") if $codetype < 2 || $codetype > 3;
    };

    {
        my $it = natatime 2, @$headers;
        while (my ($k, $v) = $it->()) {
            return (1, "remote failed header check '$k' with value '$v'") if exists $header_checks{$k} && !$header_checks{$k}->($v);
        }
    }

    return (0);
}

sub type {
    return [ grep { defined $_ && exists $VALID_CONTENT_TYPES{lc(($_ =~ m/^([^;]+)/)[0] // "")} } @_ ]->[0];
}

my $magic = File::LibMagic->new(uncompress => 1);

sub rewrite_headers_from_body {
    my ($headers, $buf) = @_;

    my $hh = Hash::MultiValue->new(@$headers);

    my $type = type($hh->{'content-type'});
    if (!$type && $buf) {
        $type = type($magic->info_from_string($buf)->{mime_type});
    }
    unless ($type) {
        my $err = sprintf "remote offered non-image content%s\n", $hh->{'content-type'} ? " ($hh->{'content-type'})" : "";
        return ($headers, $err);
    }
    $hh->set('content-type', $type);

    return ([$hh->flatten]);
}

my $furl = Furl::HTTP->new(
    timeout       => TIMEOUT,
    max_redirects => MAX_REDIRECTS,
    agent         => HEADER_UA,
    ssl_opts      => {
        CAFILE       ? (SSL_ca_file => CAFILE)            : (),
        CAPATH       ? (SSL_ca_path => CAPATH)            : (),
        IGNORE_CERTS ? (SSL_verify_callback => sub { 1 }) : (),
    },
);

# These hosts we've said "Okay, we know these resolve internally, and
# we're fine with that"
my %PARANOID_OKAY_HOSTS;

sub set_paranoid_okay_hosts {
  %PARANOID_OKAY_HOSTS = map { $_ => 1 } @_;
}

sub paranoid_okay_hosts { keys %PARANOID_OKAY_HOSTS }

if (PARANOID) {
    require Net::DNS::Paranoid;
    require Socket;
    my $dns = Net::DNS::Paranoid->new;
    $furl->{inet_aton} = sub {
        my ($host) = @_;
        if ($PARANOID_OKAY_HOSTS{$host}) {
            # Resolve normally
            Socket::inet_aton($host);
        } else {
            my ($addrs) = try { $dns->resolve($host) };
            unless (ref $addrs eq 'ARRAY') {
                $! = 14; # EFAULT = Bad address ;)
                return;
            }
            Socket::inet_aton($addrs->[0]);
        }
    }
}

sub to_app {
    return \&app;
}

sub app {
    my ($env) = @_;

    unless ($env->{REQUEST_METHOD} =~ m/^GET|HEAD$/) {
        return response(
            405,
            [],
            "request method must be GET or HEAD (not $env->{REQUEST_METHOD})"
        );
    }

    # Our Auth middleware may set this
    if ($env->{HOPSCOTCH_AUTH_ERROR}) {
        my ($code, $error) = @{ $env->{HOPSCOTCH_AUTH_ERROR} };

        return response($code, [], $error);
    }

    my $url = $env->{REQUEST_URI};

    # Valid chars are unreserved + reserved chars from https://tools.ietf.org/html/rfc3986#section-2.2
    return response(404, [], "invalid characters in URL")
      if $url =~ m{[^A-Za-z0-9\-\._~:\/\?#\[\]\@!\$&'\(\)\*\+,;=\%]}o;

    return sub {
        my ($respond) = @_;

        my $w;
        my $bytes = 0;

        my (undef, $code, $msg, $headers, $body) = try {
            my @return = $furl->request(
                method     => "GET",
                url        => $url,
                headers    => request_headers([map { (substr($_, 5) =~ s/_/-/gr) => $env->{$_} } grep { m/^HTTP_/ } keys %$env]),
                write_code => sub {
                    my ($code, $msg, $headers, $buf) = @_;

                    my ($rejected, $err) = rejected($code, $msg, $headers);
                    die $err if $rejected;

                    return if defined $buf && length $buf == 0;

                    unless (defined $w) {
                        my ($headers_out, $err) = rewrite_headers_from_body($headers, $buf);
                        die "$err\n" if $err;
                        $w = $respond->([@{response($code, $headers_out)}[0,1]]);
                    }

                    if (defined $buf) {
                        if ($env->{REQUEST_METHOD} eq "HEAD") {
                            die []; # magic to force proxy to end successfully
                        }

                        $bytes += length $buf;
                        die "remote file exceeded length limit\n" if $bytes > LENGTH_LIMIT;
                        $w->write($buf);
                    }
                }
            );

            if ($w) {
                # Flush out the response for plack
                $w->close;
            }

            return @return;
        }
        catch {
            if ($w) {
                unless (ref $_) {
                    # part way through stream so we can't return the error to the client
                    warn cleanup_error("stream aborted: $_") unless NO_WARN;
                }
                $w->close;
            }
            else {
                $respond->(response(404, [], $_));
            }
            $w = 1; # flag that we've responded
        };

        unless ($w) {
            my $err;
            return $respond->(response($code, $headers)) if $code == 304;
            (my $rejected, $err) = rejected($code, $msg, $headers);
            if ($rejected) {
                return $respond->(response(404, [], $err));
            }
            (my $headers_out, $err) = rewrite_headers_from_body($headers);
            if ($err) {
                return $respond->(response(404, [], $err));
            }
            return $respond->(response(200, $headers_out));
        }
    };
}

1;
