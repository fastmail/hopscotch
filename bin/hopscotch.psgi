#!perl
# PODNAME: hopscotch.psgi

use 5.010;
use warnings;
use strict;

use lib qw(lib);

use Hopscotch;
use Hopscotch::Auth::SHA256;

my $app = Hopscotch->to_app;
Hopscotch::Auth::SHA256->wrap($app);
