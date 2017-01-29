package Vorovaba::Actions;

use 5.010;
use strict;
use warnings;
use experimental qw/smartmatch switch/;
use utf8;
use Carp;

use Mojo::Base "Mojolicious::Controller";
use base "Vorovaba::Common";

use Yoba;

#----------------------------------------
# Создание и удаление постов
#----------------------------------------

# POST /post
sub post
{
   my $self = shift;

   # Параметры
   my $ip       = $self->tx->remote_address;
   my $board    = full_escape $self->param("board")    // "";
   my $parent   = full_escape $self->param("parent")   // "";
   my $captcha  = full_escape $self->param("captcha")  // "";
   my $subject  = full_escape $self->param("subject")  // "";
   my $youtube  = full_escape $self->param("youtube")  // "";
   my $password = full_escape $self->param("password") // "";
   my $text     = html_escape $self->param("text") // "";
   my $sage     = !!$self->param("sage");
   my $uploads  = [$youtube ? () :
                   (grep { $_ && $_->size } @{ $self->every_param("upload") })];

   # Возможности модераторов
   #----------------------------------------
   my $is_admin = $self->check_admin;
   my $is_mod   = $self->check_moderator_board($board);

   if($is_admin || $is_mod)
   {
      $text =~ s~\[color=(.*?)\](.*?)\[/color\]~<font color="$1">$2</font>~gs;
   }
   #----------------------------------------

   # Проверка полученных данных
   #----------------------------------------
   $self->stash(previous_page => "/$board" . ($parent ? "/thread/$parent" : ""));
   $self->stash(boards_list => $self->get_boards_list);
   
   $self->render_error("Некорректные данные.") and return
      unless length $board
      && length $parent
      && (!$self->config->{board}->{captcha} || length $captcha);

   $self->render_error("Пустое сообщение.") and return
      if !length $text && !@$uploads && !$youtube;

   $self->render_error("Слишком много файлов.") and return
      if @$uploads > 4;

   $self->render_error("Слово из чёрного списка.") and return
      if $self->check_blacklist($text . $subject);

   if($self->config->{board}->{captcha})
   {
      $self->render_error("Капча протухла.") and return
         unless $self->check_captcha_exists($ip);

      $self->render_error("Неправильно введена капча.") and return
         if lc $captcha ne lc $self->remove_captcha($ip);
   }

   $self->render_error("Доска /$board/ не существует.") and return
      unless $self->check_board_exists($board);

   $self->render_error("Тред /$board/$parent не существует.") and return
      if $parent && !$self->check_thread_exists($board, $parent);

   $self->render_error("Вы забанены.") and return
      if $self->check_ban($ip);

   for my $upload (@$uploads)
   {
      $self->render_error("Тип файла не разрешён.") and return
         unless $self->check_file_type_allowed($board, get_file_suffix $upload->filename);

      $self->render_error("Слишком большой файл.") and return
         unless $self->check_file_size_allowed($board, $upload->size);
   }
   #----------------------------------------

   # Создание поста
   my $number = $self->create_post(
      $ip, $board, $parent, $subject,
      $text, $password, $sage,
      $youtube, $uploads
   );

   # Очистка кеша
   #$self->cache->clear("$board*");
   $self->memcached->flush_all;

   # Возврат к доске/треду
   $self->redirect_to(sprintf "/$board/thread/%d", ($parent ? $parent : $number));
}

# POST /delete
sub delete
{
   my $self = shift;

   # Параметры
   my $board = full_escape $self->param("board");
   my $post  = full_escape $self->param("post");
   my $pass  = full_escape $self->param("password");

   # Проверка полученных данных
   $self->render_error("Некорректные данные.") and return
      unless length $board && length $post && length $pass;

   $self->render_error("Пост не существует.") and return
      unless $self->check_post_exists($board, $post);

   # Вытаскиваем данные из БД
   my $boards_collection = $self->db_boards;
   my $posts_collection  = $self->db_posts;

   # Данные по посту
   my $post_data = $posts_collection->find_one({ board => $board, number => int $post });

   # Ошибка, если пароль неправильный
   $self->render_error("Неправильный пароль.") and return
      if $pass ne $post_data->{data}->{password};

   # Удаление поста
   $self->delete_post($board, $post);

   # Очистка кеша
   #$self->cache->clear("$board*");
   $self->memcached->flush_all;

   # Возврат к доске
   $self->redirect_to("/$board");
}

#----------------------------------------
# Панель управления и модерация
#----------------------------------------

# POST /login
sub login
{
   my $self = shift;

   # Параметры
   my $pass = $self->param("password");

   # Если данные верны, сохраняем печеньки
   # и перенаправляем в админку
   if($self->check_admin($pass))
   {
      $self->session(admin_password => $pass);
      $self->redirect_to("/admin");
      return;
   }

   $self->redirect_to("/login");
}

# POST /admin
sub admin
{
   my $self = shift;

   die if $self->tx->remote_address ne "127.0.0.1";

   # Параметры
   my $action = $self->param("action");

   # Проверка полученных данных
   $self->redirect_to("/login") and return
      unless $self->check_admin;

   # Выполнение действия
   given($action)
   {
      # Создание новой доски
      when("createboard")
      {
         # Параметры
         my $name       = lc full_escape $self->param("name");
         my $title      = ucfirst full_escape $self->param("title");
         my $postername = full_escape $self->param("postername");
         my $rules      = remove_spaces $self->param("rules");
         my $thumbsize  = remove_spaces $self->param("thumbsize");
         my $maxsize    = remove_spaces $self->param("maxsize");
         my $flags      = !!$self->param("flags");
         my $formats    = [$self->param("formats")];

         # Проверка полученных данных
         $self->render_error("Некорректные данные.") and return
            unless(length $name  && length $name  <= 10 &&
                   $name =~ /\D/ &&
                   length $title && length $title <= 40 &&
                   $thumbsize >= 1 && $maxsize >= 1);

         $self->render_error("Нельзя создать доску, начинающуюся с '_'.") and return
            if $name =~ /^_/;

         $self->render_error("Доска уже существует.") and return
            if $self->check_board_exists($name);

         # Создание доски
         $self->create_board(
            $name, $title, $postername,
            $rules, $thumbsize, $maxsize,
            $flags, $formats
         );
      }

      # Удаление доски
      when("deleteboard")
      {
         # Параметры
         my $name = remove_spaces $self->param("name");

         # Проверка полученных данных
         $self->render_error("Некорректные данные.") and return
            unless length $name;

         $self->render_error("Доска не существует.") and return
            unless $self->check_board_exists($name);

         # Удаление доски
         $self->delete_board($name);
      }
   }

   # Перенаправление в админку
   #$self->cache->clear("*");
   $self->memcached->flush_all;

   $self->redirect_to("/admin");
}

# GET /mod
sub mod
{
   my $self = shift;

   return if $self->tx->remote_address ne "127.0.0.1";

   # Параметры
   my $action = $self->param("action");
   my $board  = $self->param("board");
   my $post   = $self->param("post");

   # Проверка полученных данных
   $self->redirect_to("/login") and return
      unless($self->check_admin);

   $self->render_error("Некорректные данные.") and return
      unless length $action && length $board && length $post;

   $self->render_error("Пост не существует.") and return
      unless $self->check_post_exists($board, $post);

   # Вытаскиваем данные из БД
   my $boards_collection = $self->db_boards;
   my $posts_collection  = $self->db_posts;

   # Выполнение действия
   given($action)
   {
      # Удаление поста
      when("delete")
      {
         $self->delete_post($board, $post);
      }

      # Удаление всех постов по айпи
      when("delete_all")
      {
         $self->delete_posts_by_ip($board, $post);
      }

      # Бан айпи
      when("ban")
      {
         $self->ban_poster($board, $post);
      }

      # Удаление поста и бан
      when("delete_and_ban")
      {
         $self->ban_poster($board, $post);
         $self->delete_post($board, $post);
      }

      # Удаление всех постов и бан
      when("delete_all_and_ban")
      {
         $self->ban_poster($board, $post);
         $self->delete_posts_by_ip($board, $post);
      }
   }

   #$self->cache->clear("$board*");
   $self->memcached->flush_all;

   $self->redirect_to("/$board");
}

#----------------------------------------
# 2.0
#----------------------------------------

# POST /custom/create
sub custom_create
{
   my $self = shift;

   # Параметры
   my $ip         = $self->tx->remote_address;
   my $name       = "_" . lc full_escape $self->param("name");
   my $title      = ucfirst full_escape $self->param("title");
   my $postername = full_escape $self->param("postername");
   my $password   = $self->param("password");
   my $captcha    = $self->param("captcha");

   # Проверка полученных данных
   #----------------------------------------
   $name =~ s~[^a-z0-9_]~~g;

   $self->render_error("Некорректные данные.") and return
      unless(length $name > 1  && length $name  <= 10 &&
             $name =~ /\D/ &&
             length $title && length $title <= 40 &&
             $title !~ m~[^a-z0-9а-яё ]~i &&
             length $password);

   $self->render_error("Капча протухла.") and return
      unless $self->check_captcha_exists($ip);

   $self->render_error("Неправильно введена капча.") and return
      if lc $captcha ne lc $self->remove_captcha($ip);

   $self->render_error("Доска уже существует.") and return
      if $self->check_board_exists($name);
   #----------------------------------------

   # Создание доски
   $self->create_board(
      $name, $title, $postername,
      "", 200, 10485760,
      0, ["jpg", "png", "gif"]
   );

   # Создание модератора
   $self->create_moderator($name, $password);
   $self->session(mod => $password);

   #$self->cache->clear("custom");
   $self->memcached->flush_all;

   # Перенаправление на новую доску
   $self->redirect_to("/$name");
}

# POST /custom/login
sub custom_login
{
   my $self = shift;

   my $pass = $self->param("password");
   $self->session(mod => $pass);

   $self->redirect_to("/custom");
}

# GET /modmod
sub modmod
{
   my $self = shift;

   # Параметры
   my $action = $self->param("action");
   my $board  = $self->param("board");
   my $post   = $self->param("post");

   # Проверка полученных данных
   $self->render_error("Вы не мочератор на этой доске или не залогинились.") and return
      unless $self->check_moderator_board($board);

   $self->render_error("Некорректные данные.") and return
      unless length $action && length $board && length $post;

   $self->render_error("Пост не существует.") and return
      unless $self->check_post_exists($board, $post);

   # Вытаскиваем данные из БД
   my $boards_collection = $self->db_boards;
   my $posts_collection  = $self->db_posts;

   # Выполнение действия
   given($action)
   {
      # Удаление поста
      when("delete")
      {
         $self->delete_post($board, $post);
      }

      # Удаление всех постов по айпи
      when("delete_all")
      {
         $self->render_error("Эта функция отключена.") and return
         #$self->delete_posts_by_ip($board, $post);
      }

      # Бан айпи
      # when("ban")
      # {
      #    $self->ban_poster($board, $post);
      # }

      # Удаление поста и бан
      # when("delete_and_ban")
      # {
      #    $self->ban_poster($board, $post);
      #    $self->delete_post($board, $post);
      # }

      # # Удаление всех постов и бан
      # when("delete_all_and_ban")
      # {
      #    $self->ban_poster($board, $post);
      #    $self->delete_posts_by_ip($board, $post);
      # }
   }

   #$self->cache->clear("$board*");
   $self->memcached->flush_all;

   $self->redirect_to("/$board");
}

2;
