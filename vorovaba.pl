#!/usr/bin/perl

use FindBin;
use lib "$FindBin::Bin/lib";
use Mojolicious::Commands;

Mojolicious::Commands->start_app("Vorovaba");
