use 5.010;
use warnings;
use strict;

use lib qw(t/lib);

use Test::More 0.88;

use Crypt::Mac::HMAC qw(hmac_hex);
use Hopscotch::Tester;
use MIME::Base64;

subtest "quoth the upstream '404'" => sub {
    my $key = 'abcd';

    my ($app, $tester) = Hopscotch::Tester->new_app_and_tester({
      HOPSCOTCH_KEY     => $key,
      HOPSCOTCH_NO_WARN => 1,
    });

    {
        my $url = "https://www.fastmail.com/doesnotexist.ico";
        my $mac = hmac_hex('SHA256', $key, $url);
        my $hex_url = unpack('h*', $url);

        my $res = $tester->get("$mac/$hex_url");
        is($res->code, 404, 'got 404 from upstream');
        like(
            $res->decoded_content,
            qr/E: remote returned 404/,
            "invalid URL detected"
        );
    }
};

subtest "quoth the dns, 'NXDOMAIN'" => sub {
    my $key = 'abcd';

    my ($app, $tester) = Hopscotch::Tester->new_app_and_tester({
      HOPSCOTCH_KEY     => $key,
      HOPSCOTCH_NO_WARN => 1,
    });

    {
        my $url = "https://www.thisbetternotexistthankyouverymuchahhhhhhh.com";
        my $mac = hmac_hex('SHA256', $key, $url);
        my $hex_url = unpack('h*', $url);

        my $res = $tester->get("$mac/$hex_url");
        is($res->code, 404, 'got 404 from upstream');
        like(
            $res->decoded_content,
            qr/E: cannot resolve host/i,
            "bad host detected"
        );
    }
};

done_testing;
