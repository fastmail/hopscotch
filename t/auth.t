use 5.010;
use warnings;
use strict;

use lib qw(t/lib);

use Test::More 0.88;

use Crypt::Mac::HMAC qw(hmac_hex);
use Hopscotch::Tester;
use MIME::Base64;

subtest "Auth::SHA256" => sub {
    my $key = 'abcd';

    my ($app, $tester) = Hopscotch::Tester->new_app_and_tester({
      HOPSCOTCH_KEY     => $key,
      HOPSCOTCH_NO_WARN => 1,
    });

    {
        my $res = $tester->get("");
        is($res->code, 404, 'got 404');
        like(
            $res->decoded_content,
            qr/E: invalid URL/,
            "invalid URL detected"
        );
    }

    {
        my $res = $tester->get("mac/badhex");
        is($res->code, 404, 'got 404');
        like(
            $res->decoded_content,
            qr/E: invalid characters in hex/,
            "invalid hex fragment detected"
        );
    }

    {
        my $res = $tester->get("badmac/deadbeef");
        is($res->code, 404, 'got 404');
        like(
            $res->decoded_content,
            qr/E: invalid MAC/,
            "invalid MAC detected"
        );
    }

    {
        my $url = "https://www.fastmail.com/favicon.ico";
        my $mac = hmac_hex('SHA256', $key, $url);
        my $hex_url = unpack('h*', $url);

        my $raw_get = LWP::UserAgent->new->get($url);

        my $res = $tester->get("$mac/$hex_url");
        is($res->code, 200, 'got 200');
        is(
            encode_base64($res->decoded_content, ""),
            encode_base64($raw_get->decoded_content, ""),
            "proxy worked!"
        );
    }
};

done_testing;
