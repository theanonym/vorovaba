package Vorovaba;

use 5.010;
use strict;
use warnings;
use experimental qw/smartmatch switch/;
use utf8;
use Carp;
use lib "lib";

use Mojo::Base "Mojolicious";

use MongoDB;
use Mojolicious::Plugin::Config;

use Yoba;
#use Mojolicious::Plugin::YobaLog;
use Mojolicious::Plugin::YobaMemcached;
use Mojolicious::Plugin::YobaCaptcha;

our $VERSION = "2.0.0";

use Data::Dump qw/dump/;

BEGIN {
   $ENV{MOJO_MAX_MESSAGE_SIZE} = 10 * 1024 * 1024; # 10MB
   #$ENV{MOJO_MODE} = "production";
   $ENV{MOJO_MODE} = "development";
};

sub startup
{
   my $self = shift;

   # Плагины
   #----------------------------------------
   # Конфиг
   $self->plugin("Config");

   # Капча
   $self->plugin("YobaCaptcha" => {
      size => 20,
      color => "gray",
      wave_amplitude => 1,
      wave_length => 30,
   });

   # Определение страны постера
   #$self->plugin("Geo");

   # Кеш
   $self->plugin("YobaMemcached", {
    servers => [ { address => "localhost:11211" } ],
    nowait => 1,
    utf8 => 1,
    #namespace => "govno:",
   });

   # Логгирование
   #$self->plugin("YobaLog");
   #----------------------------------------

   # Сессии
   #----------------------------------------
   $self->sessions->cookie_name("vorovaba");
   $self->sessions->default_expiration(60 * 60 * 24 * 30);
   #----------------------------------------

   # Типы контента
   #----------------------------------------
   $self->types->type(txt => "text/plain; charset=utf-8");
   $self->types->type(swf => "application/x-shockwave-flash");
   #----------------------------------------

   # Заголовки
   #----------------------------------------

   # Здесь можно переопределить стандартные или
   # добавить свои заголовки.
   my %headers = (
      "Server"       => "Shit",
      "X-Powered-By" => "Urine",
   );

   while(my($key, $value) = each %headers)
   {
      $self->hook(before_dispatch => sub { $_[0]->res->headers->header($key => $value) });
   }
   #----------------------------------------

   # Доступ к БД
   #----------------------------------------
   my $db = MongoDB::Connection->new(
      host => $self->config->{database}->{host},
   )->get_database($self->config->{database}->{name});

   $self->helper(db         => sub { MongoDB::Connection->new(
      host => $self->config->{database}->{host},
   )->get_database($self->config->{database}->{name}) } );
   $self->helper(db_boards  => sub { $_[0]->db->get_collection("boards")  });
   $self->helper(db_posts   => sub { $_[0]->db->get_collection("posts")   });
   $self->helper(db_banlist => sub { $_[0]->db->get_collection("banlist") });
   $self->helper(db_captcha => sub { $_[0]->db->get_collection("captcha") });
   $self->helper(db_mods    => sub { $_[0]->db->get_collection("mods")    });
   #----------------------------------------

   # Маршруты
   #----------------------------------------
   my $routes = $self->routes;

   # Главная
   $routes->get("/" => sub { $_[0]->redirect_to("/main") });
   $routes->get("/main")->to("pages#main");
   $routes->get("/faq")->to("pages#faq");
   $routes->get("/search")->to("pages#search");

   # Панель управления
   $routes->get("/login")->to("pages#login");
   $routes->post("/login")->to("actions#login");
   $routes->get("/admin")->to("pages#admin");
   $routes->post("/admin")->to("actions#admin");

   # 2.0
   $routes->get("/custom")->to("pages#custom");
   $routes->get("/custom/create")->to("pages#custom_create");
   $routes->post("/custom/create")->to("actions#custom_create");
   $routes->get("/custom/login")->to("pages#custom_login");
   $routes->post("/custom/login")->to("actions#custom_login");

   # Модерация
   $routes->get("/mod")->to("actions#mod");
   $routes->get("/modmod")->to("actions#modmod");

   # Капча
   $routes->get("/captcha")->to("pages#captcha_image");

   # Доски, треды, каталог
   $routes->get("/:board")->to("pages#board", page => 1);
   $routes->route("/:board/:page", page => qr~\d+~)->via("GET")->to("pages#board");
   $routes->route("/:board/thread/:thread", thread => qr~\d+~)->via("GET")->to("pages#thread");
   $routes->get("/:board/catalog")->to("pages#catalog");

   # Создание и удаление постов
   $routes->post("/post")->to("actions#post");
   $routes->post("/delete")->to("actions#delete");

   $routes->any("/*path")->to(
      "pages#error",
      message => "Ничего не найдено 404 раза."
   );
   #----------------------------------------

   $self->db_captcha->remove;
}

2;
