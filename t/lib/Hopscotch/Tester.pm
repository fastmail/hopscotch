use 5.010;
use strict;
use warnings;
package Hopscotch::Tester;

use LWP::Protocol::PSGI;
use LWP::UserAgent;
use MIME::Base64 qw(decode_base64);

my $baseport = 443;

my $host = 'hopscotch.local';
my $port = sub { $baseport++ };

{
    package Hopscotch::Tester::LWP::Wrapper;

    sub new {
        my ($class, $hostport, $guard) = @_;

        return bless {
            lwp          => LWP::UserAgent->new,
            hostport     => $hostport,
            guard        => $guard,
        }, $class;
    }

    sub url {
        my ($self) = @_;

        return "https://" . $self->{hostport} . "/";
    }

    sub _request {
        my ($self, $what, $fragment, @args) = @_;

        $self->{lwp}->$what(
            $self->url . $fragment,
            @args,
        );
    }

    sub post   { shift->_request('post',   @_) }
    sub get    { shift->_request('get',    @_) }
    sub put    { shift->_request('put',    @_) }
    sub delete { shift->_request('delete', @_) }
}

sub new_app_and_tester {
    my ($class, $args) = @_;

    local %ENV = %ENV;

    $ENV{$_} = $args->{$_} for keys %$args;

    my $app = do "bin/hopscotch.psgi"
        || die "Failed to execute ./bin/hopscotch: $@\n";

    my $wrapped_app = sub {
        my ($env) = @_;

        my $res = $app->($env);

        Plack::Util::response_cb($res, sub {
            my $res = shift;

            return sub {
                my $chunk = shift;
                return $chunk;
            }
        });
    };

    my $hostport = "$host" . ":" . $port->();

    my $guard = LWP::Protocol::PSGI->register(
        $wrapped_app,
        host => qr/\Q$hostport\E\z/i,
    );

    my $lwp = Hopscotch::Tester::LWP::Wrapper->new(
        $hostport,
        $guard,
    );

    return ($wrapped_app, $lwp);
}

1;
