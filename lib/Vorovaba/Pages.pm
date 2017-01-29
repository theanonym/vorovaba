package Vorovaba::Pages;

use 5.010;
use strict;
use warnings;
use utf8;
use Carp;

use Mojo::Base "Mojolicious::Controller";
use base "Vorovaba::Common";

use Yoba;

use Date::Format qw/time2str/;
use Data::Dump qw/dump/;

#----------------------------------------
# Основные страницы
#----------------------------------------

# GET /main
sub main
{
   my $self = shift;

   my($ip) = $self->tx->remote_address;

   $self->render;
}

# GET /faq
sub faq
{
   my $self = shift;

   $self->render(boards_list => $self->get_boards_list);
}

# GET /search
sub search
{
   my $self = shift;
return;
   # Параметры
   my $query = full_escape $self->param("query");

   # Проверка полученных данных
   $self->render_error("Некорректные данные.") and return
      unless length $query;

   $self->render_error("Ошибка конпеляции регулярного выражения.") and return
      unless eval { qr/$query/; 1 };

   # Вытаскиваем данные из БД
   my $boards_collection = $self->db_boards;
   my $posts_collection  = $self->db_posts;

   my $board_data  = $boards_collection->find_one({ name => "b" });

   my $posts_cursor = $posts_collection->find(
      { "data.text" => qr/$query/i }
   )->limit(50)->sort(
      { time => -1 }
   );

   # Отображение страницы
   $self->render(
      custom => 0,

      thread => 0,

      board_data  => $board_data,
      boards_list => $self->get_boards_list,

      posts_cursor => $posts_cursor,

      query => $query,
   );
}

#----------------------------------------
# Панель управления
#----------------------------------------

# GET /login
sub login
{
   my $self = shift;

   # Если админ уже залогинился, перенаправляем
   # сразу в админку
   $self->redirect_to("/admin") and return
      if $self->check_admin;

   $self->render(boards_list => $self->get_boards_list);
}


# GET /admin
sub admin
{
   my $self = shift;

   # Если админ не залогинился, перенаправляем
   # на страницу входа
   $self->redirect_to("/login") and return
      unless $self->check_admin;
      
   $self->render;
}

#----------------------------------------
# Доски, треды, каталог
#----------------------------------------

# GET /:board/:page
sub board
{
   my $self = shift;
   my($url, $ip) = (
      $self->req->url->path,
      $self->tx->remote_address,
   );

   # Параметры
   my $board  = $self->stash("board");
   my $page   = $self->stash("page");
   my $custom = $board =~ /^_/;

   # Проверка полученных данных
   $self->render_error("Ничего не найдено 404 раза.", 404) and return
      unless $self->check_board_exists($board);

   # $self->redirect_to("/$board/1") and return
   #    if $page == 1 && $url !~ m~/1/?$~;

   # Вытаскиваем данные из БД
   my $boards_collection = $self->db_boards;
   my $posts_collection  = $self->db_posts;

   # Данные по доске и список досок
   my $board_data  = $boards_collection->find_one({ name => $board });

   # ОП-посты
   my $opposts_data = $posts_collection->find(
      { board => $board, parent => 0 }
   );

   # Определяем количество тредов и страниц

   my $threads_per_page = $self->config->{board}->{threads_per_page};
   my $posts_per_thread = $self->config->{board}->{posts_per_thread};
   my $threads_count = $opposts_data->count;
   my $pages_count = ceil($threads_count / $threads_per_page) || 1;

   # Перенаправляем на последнюю страницу, если страница не существует
   $self->redirect_to("/$board/$pages_count") and return
      if $page > $pages_count;

   # Данные по ОП-постам
   my $opposts_cursor = $posts_collection->find(
      { board => $board, parent => 0 }
   )->sort(
      { lastpost => -1 }
   )->skip(($page - 1) * $threads_per_page)->limit($threads_per_page);

   # Данные по постам
   my $posts_cursors;
   while(my $oppost_data = $opposts_cursor->next)
   {
      $posts_cursors->{$oppost_data->{number}} = $posts_collection->find(
         { board => $board, parent => int $oppost_data->{number} }
      )->sort(
         { time => 1 }
      )->skip(max($oppost_data->{posts_count} - $posts_per_thread, 0));
   }

   $opposts_cursor->reset;

   # Отображение страницы
   $self->render(
      custom => $custom,

      board  => $board,
      thread => 0,

      board_data  => $board_data,
      boards_list => $self->get_boards_list,

      opposts_cursor => $opposts_cursor,
      posts_cursors  => $posts_cursors,

      threads_per_page => $threads_per_page,
      posts_per_thread => $posts_per_thread,
      threads_count    => $threads_count,
      pages_count      => $pages_count,
   );
}

# GET /:board/thread/:thread
sub thread
{
   my $self = shift;

   # Параметры
   my $board  = $self->stash("board");
   my $thread = $self->stash("thread");
   my $custom = $board =~ /^_/;

   # Проверка полученных данных
   $self->render_error("Ничего не найдено 404 раза.", 404) and return
      unless $self->check_board_exists($board) && $self->check_thread_exists($board, $thread);

   # Вытаскиваем данные из БД
   my $boards_collection = $self->db_boards;
   my $posts_collection  = $self->db_posts;

   # Данные по доске и список досок
   my $board_data  = $boards_collection->find_one({ name => $board });

   # ОП-пост
   my $oppost_data = $posts_collection->find_one(
      { board => $board, parent => 0, number => int $thread }
   );

   # Остальные посты (сортировка по времени)
   my $posts_cursor = $posts_collection->find(
      { board => $board, parent => int $thread }
   )->sort({ time => 1 });

   # Отображение страницы
   $self->render(
      custom => $custom,

      board  => $board,
      thread => $thread,

      board_data  => $board_data,
      boards_list => $self->get_boards_list,

      oppost_data  => $oppost_data,
      posts_cursor => $posts_cursor,
   );
}

# GET /:board/catalog
sub catalog
{
   my $self = shift;

   # Параметры
   my $board = $self->stash("board");
   my $custom = $board =~ /^_/;

   # Проверка полученных данных
   $self->render_error("Ничего не найдено 404 раза.", 404) and return
      unless $self->check_board_exists($board);

   # Вытаскиваем данные из БД
   my $boards_collection = $self->db_boards;
   my $posts_collection  = $self->db_posts;

   # Данные по доске и список досок
   my $board_data  = $boards_collection->find({ name => $board })->next;

   # Данные по ОП-постам
   my $opposts_cursor = $posts_collection->find(
      { board => $board, parent => 0 }
   )->sort(
      { lastpost => -1 }
   );

   # Отображение страницы
   $self->render(
      custom => $custom,

      board  => $board,

      board_data  => $board_data,
      boards_list => $self->get_boards_list,

      opposts_cursor => $opposts_cursor,
   );
}

#----------------------------------------
# Капча
#----------------------------------------

# GET /captcha
sub captcha_image
{
   my $self = shift;
   my $ip = $self->tx->remote_address;

   my $new = !!$self->param("new");
   $new = 1;

   #$self->app->log->info("check");
   if($new || !$self->check_captcha_exists($ip)) {
      #$self->app->log->info("make");
      $self->make_captcha($ip);
   }

   #$self->res->headers->header("content-type" => "image/png");
   #$self->render_static(catfile("..", "captcha", "$ip.png"));

   $self->reply->static(catfile("..", "captcha", "$ip.png"));
}

#----------------------------------------
# 2.0
#----------------------------------------

# GET /custom
sub custom
{
   my $self = shift;

   my $boards_list = $self->get_boards_list;

   my $postcount = {
      map {
         $_->[0] => sum($self->count_posts_by_board($_->[0]));
      } grep {
         $_->[0] =~ /^_/
      } @$boards_list
   };

   # Отображение страницы
   $self->render(
      custom => 0,

      boards_list => $boards_list,

      postcount => $postcount,
   );
}

# GET /custom/create
sub custom_create
{
   my $self = shift;

   $self->render;
}

# GET /custom/login
sub custom_login
{
   my $self = shift;

   $self->render;
}

sub error
{
   my $self = shift;

   $self->render;
}

2;
