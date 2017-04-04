use 5.010;
use strict;
use warnings;
package Hopscotch::Auth::SHA256;

use Crypt::Mac::HMAC qw(hmac_hex);

use constant KEY => $ENV{HOPSCOTCH_KEY} // die "HOPSCOTCH_KEY not set\n";

sub error {
    my ($app, $env, $code, $error) = @_;

    $env->{HOPSCOTCH_AUTH_ERROR} = [ $code, $error ];

    return $app->($env);
}

sub wrap {
    my ($class, $app) = @_;

    return sub {
        my ($env) = @_;

        my (undef, $mac, $hexurl) = split '/', $env->{REQUEST_URI};

        unless (defined $mac && defined $hexurl) {
            return error($app, $env,
                404 => "invalid URL structure (MAC/hex)",
            );
        }

        unless ($hexurl =~ m/^[0-9a-f]+$/) {
            return error($app, $env,
                404 => "invalid characters in hex fragment",
            );
        }

        my $url = pack "h*", $hexurl;
        my $our_mac = hmac_hex('SHA256', KEY, $url);

        unless (lc($mac) eq lc($our_mac)) {
            return error($app, $env,
                404 => "invalid MAC"
            );
        }

        $env->{REQUEST_URI} = $url;

        $app->($env);
    }
}

1;
