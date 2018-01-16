use 5.010;
use warnings;
use strict;

use lib qw(t/lib);

use Test::More 0.88;

BEGIN {
    my $skip;

    my @req = qw(
        Imager
        Imager::File::JPEG
        Imager::File::PNG
    );

    my @missing;

    for my $mod (@req) {
        push @missing, $mod unless eval "require $mod";
    }

    plan skip_all => "Missing @missing" if @missing;
}

use Crypt::Mac::HMAC qw(hmac_hex);
use Hopscotch::Tester;
use Hopscotch::Resize;
use MIME::Base64;

my $key = 'abcd';
my ($app, $tester) = Hopscotch::Tester->new_app_and_tester({
    HOPSCOTCH_KEY     => $key,
    HOPSCOTCH_NO_WARN => 1,

    wrap => sub {
      my $app = shift;

      return Hopscotch::Resize->wrap($app);
    },
});

my $url = "https://www.fastmail.com/favicon.ico";
my $raw_get = LWP::UserAgent->new->get($url);

subtest "no resize, just works" => sub {
    my $mac = hmac_hex('SHA256', $key, $url);
    my $hex_url = unpack('h*', $url);

    my $res = $tester->get("$mac/$hex_url");
    is($res->code, 200, 'got 200');
    is($res->header('Content-Type'), 'image/png', 'ct is right');
    is(
        encode_base64($res->decoded_content, ""),
        encode_base64($raw_get->decoded_content, ""),
        "proxy worked!"
    );
};

subtest "max above" => sub {
    my $key = 'abcd';

    my $mac = hmac_hex('SHA256', $key, $url);
    my $hex_url = unpack('h*', $url);

    my $res = $tester->get("$mac/$hex_url?max-height=1000");
    is($res->code, 200, 'got 200');
    is($res->header('Content-Type'), 'image/png', 'ct is right');
    is(
        encode_base64($res->decoded_content, ""),
        encode_base64($raw_get->decoded_content, ""),
        "proxy worked!"
    );
};

subtest "maxx below" => sub {
    my $key = 'abcd';

    my $mac = hmac_hex('SHA256', $key, $url);
    my $hex_url = unpack('h*', $url);

    my $res = $tester->get("$mac/$hex_url?max-height=4");
    is($res->code, 200, 'got 200');
    is($res->header('Content-Type'), 'image/png', 'ct is right');
    is(
        encode_base64($res->decoded_content, ""),
        'iVBORw0KGgoAAAANSUhEUgAAAAQAAAAECAYAAACp8Z5+AAAAT0lEQVQImQFEALv/AQAAAABFV38I+/0CBdrqEfoBPVGCIQQD/mUBAQAaCwb72QQcEfQv9foEWw8I+v4HBf00BCAS8t7v9weZAAAABOz0CfEArxjo11v9iwAAAABJRU5ErkJggg==',
        "proxy worked!"
    );
};

subtest "maxy below" => sub {
    my $key = 'abcd';

    my $mac = hmac_hex('SHA256', $key, $url);
    my $hex_url = unpack('h*', $url);

    my $res = $tester->get("$mac/$hex_url?max-width=4");
    is($res->code, 200, 'got 200');
    is($res->header('Content-Type'), 'image/png', 'ct is right');
    is(
        encode_base64($res->decoded_content, ""),
        'iVBORw0KGgoAAAANSUhEUgAAAAQAAAAECAYAAACp8Z5+AAAAT0lEQVQImQFEALv/AQAAAABFV38I+/0CBdrqEfoBPVGCIQQD/mUBAQAaCwb72QQcEfQv9foEWw8I+v4HBf00BCAS8t7v9weZAAAABOz0CfEArxjo11v9iwAAAABJRU5ErkJggg==',
        "proxy worked!"
    );
};

subtest "reformat, no change" => sub {
    my $key = 'abcd';

    my $mac = hmac_hex('SHA256', $key, $url);
    my $hex_url = unpack('h*', $url);

    my $res = $tester->get("$mac/$hex_url?format=png");
    is($res->code, 200, 'got 200');
    is($res->header('Content-Type'), 'image/png', 'ct is right');
    is(
        encode_base64($res->decoded_content, ""),
        encode_base64($raw_get->decoded_content, ""),
        "proxy worked!"
    );
};

subtest "reformat to jpeg" => sub {
    my $key = 'abcd';

    my $mac = hmac_hex('SHA256', $key, $url);
    my $hex_url = unpack('h*', $url);

    my $res = $tester->get("$mac/$hex_url?format=jpeg");
    is($res->code, 200, 'got 200');
    is($res->header('Content-Type'), 'image/jpeg', 'ct is right');
    is(
        encode_base64($res->decoded_content, ""),
        '/9j/4AAQSkZJRgABAQAAAQABAAD/2wBDAAgGBgcGBQgHBwcJCQgKDBQNDAsLDBkSEw8UHRofHh0aHBwgJC4nICIsIxwcKDcpLDAxNDQ0Hyc5PTgyPC4zNDL/2wBDAQkJCQwLDBgNDRgyIRwhMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjL/wAARCAAQABADASIAAhEBAxEB/8QAHwAAAQUBAQEBAQEAAAAAAAAAAAECAwQFBgcICQoL/8QAtRAAAgEDAwIEAwUFBAQAAAF9AQIDAAQRBRIhMUEGE1FhByJxFDKBkaEII0KxwRVS0fAkM2JyggkKFhcYGRolJicoKSo0NTY3ODk6Q0RFRkdISUpTVFVWV1hZWmNkZWZnaGlqc3R1dnd4eXqDhIWGh4iJipKTlJWWl5iZmqKjpKWmp6ipqrKztLW2t7i5usLDxMXGx8jJytLT1NXW19jZ2uHi4+Tl5ufo6erx8vP09fb3+Pn6/8QAHwEAAwEBAQEBAQEBAQAAAAAAAAECAwQFBgcICQoL/8QAtREAAgECBAQDBAcFBAQAAQJ3AAECAxEEBSExBhJBUQdhcRMiMoEIFEKRobHBCSMzUvAVYnLRChYkNOEl8RcYGRomJygpKjU2Nzg5OkNERUZHSElKU1RVVldYWVpjZGVmZ2hpanN0dXZ3eHl6goOEhYaHiImKkpOUlZaXmJmaoqOkpaanqKmqsrO0tba3uLm6wsPExcbHyMnK0tPU1dbX2Nna4uPk5ebn6Onq8vP09fb3+Pn6/9oADAMBAAIRAxEAPwDx3T9BgubSGe4neITfdYAFc5xg+hqS88ORx29xJaSyzmBS0hC/KuO3Hf8AlVnT/FGm2umx2k+lyS7VIZfN+Q8+mM/rT7/xmtxpb2NrbNaxbcRpEQqr78ck+55rW8bWSJs76s//2Q==',
        "proxy worked!"
    );
};

subtest "reformat and resize" => sub {
    my $key = 'abcd';

    my $mac = hmac_hex('SHA256', $key, $url);
    my $hex_url = unpack('h*', $url);

    my $res = $tester->get("$mac/$hex_url?format=jpeg&max-height=3&max-width=3");
    is($res->code, 200, 'got 200');
    is($res->header('Content-Type'), 'image/jpeg', 'ct is right');
    is(
        encode_base64($res->decoded_content, ""),
        '/9j/4AAQSkZJRgABAQAAAQABAAD/2wBDAAgGBgcGBQgHBwcJCQgKDBQNDAsLDBkSEw8UHRofHh0aHBwgJC4nICIsIxwcKDcpLDAxNDQ0Hyc5PTgyPC4zNDL/2wBDAQkJCQwLDBgNDRgyIRwhMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjL/wAARCAADAAMDASIAAhEBAxEB/8QAHwAAAQUBAQEBAQEAAAAAAAAAAAECAwQFBgcICQoL/8QAtRAAAgEDAwIEAwUFBAQAAAF9AQIDAAQRBRIhMUEGE1FhByJxFDKBkaEII0KxwRVS0fAkM2JyggkKFhcYGRolJicoKSo0NTY3ODk6Q0RFRkdISUpTVFVWV1hZWmNkZWZnaGlqc3R1dnd4eXqDhIWGh4iJipKTlJWWl5iZmqKjpKWmp6ipqrKztLW2t7i5usLDxMXGx8jJytLT1NXW19jZ2uHi4+Tl5ufo6erx8vP09fb3+Pn6/8QAHwEAAwEBAQEBAQEBAQAAAAAAAAECAwQFBgcICQoL/8QAtREAAgECBAQDBAcFBAQAAQJ3AAECAxEEBSExBhJBUQdhcRMiMoEIFEKRobHBCSMzUvAVYnLRChYkNOEl8RcYGRomJygpKjU2Nzg5OkNERUZHSElKU1RVVldYWVpjZGVmZ2hpanN0dXZ3eHl6goOEhYaHiImKkpOUlZaXmJmaoqOkpaanqKmqsrO0tba3uLm6wsPExcbHyMnK0tPU1dbX2Nna4uPk5ebn6Onq8vP09fb3+Pn6/9oADAMBAAIRAxEAPwDzOCztTbxE20JOwclB6UUUVoQf/9k=',
        "proxy worked!"
    );
};

done_testing;
