use 5.010;
use warnings;
use strict;

use lib qw(t/lib);

use Test::More 0.88;

use Crypt::Mac::HMAC qw(hmac_hex);

BEGIN { $ENV{HOPSCOTCH_PARANOID} = 1; };

use Hopscotch::Tester;
use MIME::Base64;
use Socket qw(inet_aton inet_ntoa);

subtest "paranoid and paranoid okay bypass" => sub {
    my $key = 'abcd';

    my ($app, $tester) = Hopscotch::Tester->new_app_and_tester({
      HOPSCOTCH_KEY     => $key,
      HOPSCOTCH_NO_WARN => 1,
    });

    my $res = inet_aton("localhost");
    unless ($res && (my $ip = inet_ntoa($res)) =~ /^127/) {
      plan skip_all => "localhost didn't resolve to 127.x.x.x? (got $ip)";
    }

    my $url = "https://localhost/";
    my $mac = hmac_hex('SHA256', $key, $url);
    my $hex_url = unpack('h*', $url);

    # Baseline test

    {
        my $res = $tester->get("$mac/$hex_url");
        like(
            $res->decoded_content,
            qr/cannot resolve host/i,
            "could not resolve localhost with no bypass"
        );
    }

    # Not the host we are testing with
    Hopscotch::set_paranoid_okay_hosts('localhostx');

    {
        my $res = $tester->get("$mac/$hex_url");
        like(
            $res->decoded_content,
            qr/cannot resolve host/i,
            "could not resolve localhost with different bypass"
        );
    }

    # A good bypass
    Hopscotch::set_paranoid_okay_hosts('localhost');

    is([Hopscotch::paranoid_okay_hosts()]->[0], 'localhost', 'good get');

    {
        my $res = $tester->get("$mac/$hex_url");
        unlike(
            $res->decoded_content,
            qr/cannot resolve host/i,
            "able to resolve localhost now with bypass"
        );
    }

    # Works with multiples too
    Hopscotch::set_paranoid_okay_hosts(qw(
      localhost
      localfoo
    ));

    {
        my $res = $tester->get("$mac/$hex_url");
        unlike(
            $res->decoded_content,
            qr/cannot resolve host/i,
            "able to resolve localhost now with multiple bypasses"
        );
    }

    # Clear it
    Hopscotch::set_paranoid_okay_hosts();

    {
        my $res = $tester->get("$mac/$hex_url");
        like(
            $res->decoded_content,
            qr/cannot resolve host/i,
            "could not resolve localhost after setting to empty list"
        );
    }
};

done_testing;
