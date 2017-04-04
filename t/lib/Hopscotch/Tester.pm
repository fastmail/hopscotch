use 5.010;
use strict;
use warnings;
package Hopscotch::Tester;

use LWP::Protocol::PSGI;
use LWP::UserAgent;

my $baseport = 443;

my $host = 'hopscotch.local';
my $port = sub { $baseport++ };

{
    package Hopscotch::Tester::LWP::Wrapper;

    sub new {
        my ($class, $hostport, $guard) = @_;

        return bless {
            lwp      => LWP::UserAgent->new,
            hostport => $hostport,
            guard    => $guard,
        }, $class;
    }

    sub _request {
        my ($self, $what, @args) = @_;

        $self->lwp->$what($self->{hostport}, @args);
    }

    sub post   { shift->_request('post',   @_) }
    sub get    { shift->_request('get',    @_) }
    sub put    { shift->_request('put',    @_) }
    sub delete { shift->_request('delete', @_) }
}

sub app_and_tester {
    my ($class, $args) = @_;

    local $ENV{$_} = $args->{$_} for keys %$args;

    my $app = do "../bin/hopscotch.psgi";

    my $hostport = "$host" . ":" . $port->();

    my $guard = LWP::Protocol::PSGI->register(
        $app,
        host => qr/\Q$hostport\E\z/i,
    );

    my $lwp = Hopscotch::Tester::LWP::Wrapper->new($hostport, $guard);

    return ($app, $lwp);
}
