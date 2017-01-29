package Mojolicious::Plugin::YobaMemcached;

use 5.010;
use strict;
use warnings;
use utf8;
use Carp;

use base "Mojolicious::Plugin";

use Cache::Memcached::Fast;

use Yoba;

sub register
{
   my($self, $app, $conf) = @_;

   my $memcached = new Cache::Memcached::Fast($conf);

   $memcached->flush_all;

   $app->helper(memcached => sub { $memcached });

   $app->hook(
      after_dispatch => sub {
         my($c) = @_;
         my($req, $res) = ($c->req, $c->res);
         my $path = $req->url->path;

         $path =~ s~/$~~;
         $path =~ s~/1$~~;
         return unless($req->method eq "GET" && $res->code == 200 && $res->headers->content_type =~ /html/);
         return if $path =~ m~\.|^/captcha|^/mod|^/search~;

         unless($memcached->get($path))
         {
            $c->app->log->info("[Memcached] store page '$path'");
            $memcached->set($path, $res->body);
         }
      },
   );

   $app->hook(
      before_dispatch => sub {
         my($c) = @_;
         my($req, $res) = ($c->req, $c->res);
         my $path = $req->url->path;

         $path =~ s~/$~~;
         $path =~ s~/1$~~;
         return unless $req->method eq "GET";
         return if $path =~ m~\.|^/captcha|^/mod|^/search|^/parashometr~;

         my $data = $memcached->get($path);

         if($data)
         {
            $c->app->log->info("[Memcached] render stored page '$path'.");
            $c->res->headers->add("X-Cached" => "Yes");
            #$c->render_data($data, format => "html");
            $c->render(data => $data, format => "html");
         }
         else
         {
            $c->res->headers->add("X-Cached" => "No");
         }
      },
   );
}

2;
