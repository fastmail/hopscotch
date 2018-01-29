use 5.010;
use strict;
use warnings;
package Hopscotch::Resize;

use Crypt::Mac::HMAC qw(hmac_hex);
use Plack::Request;
use Plack::Middleware::BufferedStreaming;
use Imager;

# Handle resizing/reformating of images through:
#
# psgi.hopscotch.format
# psgi.hopscotch.max-height
# psgi.hopscotch.max-width

sub wrap {
    my ($class, $app) = @_;

    return sub {
        my ($env) = @_;

        my $req = Plack::Request->new($env);

        my %arg = map {
            $_ => $env->{"psgi.hopscotch.$_"} . "",
        } grep {
            $env->{"psgi.hopscotch.$_"}
        } qw(format max-height max-width);

        unless (%arg) {
            # Not trying to modify? Return a streamed response
            return $app->($env);
        }

        # Kill query string
        $env->{REQUEST_URI} =~ s/\?.*$//;

        # Force streaming to give us full response so we can
        # mangle it
        $app = Plack::Middleware::BufferedStreaming->wrap(
            $app,
            force => 1,
        );

        my $res = $app->($env);

        my $indata = join('', @{$res->[2]});

        # If we fail to parse the image just return whatever response
        # we had to the client
        my $img = Imager->new(data => $indata)
            or return $res;

        # Pull out content-type to figure out image type
        my $intype;

        for my $i (0..@{ $res->[1] }) {
            if (lc $res->[1][$i] eq 'content-type') {
                (undef, $intype) = splice @{ $res->[1] }, $i, 2;

                last;
            }
        }

        # Restore content-type incase we need to bail out
        push @{ $res->[1] }, (
            'Content-Type' => $intype,
        );

        $intype =~ s{image/}{};

        my $outtype = $arg{format} ? "$arg{format}" : "$intype";

        unless ($Imager::formats{$outtype}) {
            # We can't produce the requested type? Give up
            return $res;
        }

        my $changed = 0;

        if ($arg{'max-width'} || $arg{'max-height'}) {
            my $height = $img->getheight;
            my $width = $img->getwidth;

            if (
                   ( $arg{'max-height'} && $height > $arg{'max-height'} )
                || ( $arg{'max-width'} && $width > $arg{'max-width'} )
            ) {
                $img = $img->scale(
                    ( $arg{'max-width'} ? ( xpixels => $arg{'max-width'} ) : () ), 
                    ( $arg{'max-height'} ? ( ypixels => $arg{'max-height'} ) : () ),
                    type => 'min',
                );

                unless ($img) {
                    # Failed to resize? Give up
                    return $res;
                }

                $changed = 1;
            }
        }

        unless ($changed || $outtype ne $intype) {
            # No actual changes to make? Return the original response
            return $res;
        }

        my $outdata;

        unless ($img->write(
            type => $outtype,
            data => \$outdata,
        )) {
            # failed to write out new image? Give up
            return $res;
        }

        # Remove content-type, add ours
        pop @{ $res->[1] } for 1..2;

        push @{ $res->[1] }, (
            'Content-Type' => "image/$outtype",
        );

        return [ $res->[0], $res->[1], [ $outdata ] ];
    }
}

1;
