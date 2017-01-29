package Vorovaba::Common;

use 5.010;
use strict;
use warnings;
use experimental qw/smartmatch switch/;
use utf8;
use Carp;

use Image::Magick;

use Yoba;

#----------------------------------------
# Создание и удаление досок и постов
#----------------------------------------

sub create_board($$$$$$$$)
{
   my $self = shift;
   my($name, $title, $postername,
      $rules, $thumbsize, $maxsize,
      $flags, $formats
   ) = @_;

   # Вставка данных в БД
   my $boards_collection = $self->db_boards;

   $boards_collection->insert({
      name       => $name,
      title      => $title,
      postername => $postername,

      flags => $flags,

      lastpost => 0,

      options => {
         rules     => $rules,
         maxlength => $maxsize,
         thumbsize => $thumbsize,
         formats   => $formats,
      },
   });

   return;
}

sub create_post($$$$$$$$)
{
   my $self = shift;
   my($ip, $board, $parent, $subject,
      $text, $password, $sage,
      $youtube, $uploads
   ) = @_;

   # Обработка данных
   #----------------------------------------
   $subject = substr($subject, 0, 30) if length $subject > 30;
   $youtube = substr($youtube, 0, 15) if length $youtube > 15;

   $self->do_markdown($board, $parent, \$text);

   # Формирование данных для вставки в БД
   #----------------------------------------
   my $boards_collection = $self->db_boards;
   my $posts_collection  = $self->db_posts;

   my $board_data  = $boards_collection->find_one({ name => $board });

   my $number = $board_data->{lastpost} + 1;
   my $time = time;

   my $post_data = {
      board   => $board,
      parent  => int $parent,
      number  => int $number,
      time    => int $time,
      ip      => $ip,
      # country => ($board_data->{flags} ? $self->get_ip_country($ip) : ""),
      country => "",

      posts_count => 0,
      lastpost    => ($parent ? 0 : $time),

      data => {
         sage     => $sage,
         subject  => $subject,
         text     => $text,
         password => $password,
         youtube  => $youtube,
      },
   };

   # Обработка загруженных файлов
   for my $upload (@$uploads)
   {
      # Сохранение файла и генерация
      my($fname, $width, $height, $thumb_width, $thumb_height)
         = $self->save_file($board, $upload);

      # Добавляем к данным картинку
      push @{ $post_data->{images} }, {
         fname => $fname,

         size         => int $upload->size,
         width        => int $width,
         height       => int $height,
         thumb_width  => int $thumb_width,
         thumb_height => int $thumb_height,
      };
   }

   # Обновление БД
   #----------------------------------------

   # Вставляем пост в базу
   $posts_collection->insert($post_data);

   # Увеличиваем на 1 последний пост на доске
   $boards_collection->update(
      { name => $board },
      { '$inc' => { lastpost => 1 } }
   );

   if($parent)
   {
      # Увеличение на 1 количество постов в треде
      $posts_collection->update(
         { board => $board, number => int $parent },
         { '$inc' => { posts_count => 1 } }
      );

      # Изменение времени последнего поста в треде (бамп)
      if(!$sage)
      {
         $posts_collection->update(
            { board => $board, number => int $parent },
            { '$set' => { lastpost => int $time } },
         );
      }
   }
   #----------------------------------------

   return $number;
}

sub do_markdown($$$)
{
   my $self = shift;
   my($board, $parent, $text) = @_;

   for($$text)
   {
      # Вытаскиваем блоки кода
      my @code = m~\[code(?:\=.*?)?\]\s*(.*?)\s*\[/code\]~gms;
      s~(\[code(?:\=.*?)?\]).*?(\[/code\])~$1$2~gms;

      # Разметка
      s~\n~<br>\n~g; # Новая строка
      s~(https?://.*?)(\s|$)~<a href="$1">$1</a>$2~g;
      s~(&gt;&gt;(\d+))~<a href="/$board/thread/$parent#$2">$1</a>~g;
      s~^(&gt;.*?)$~<span class="markdown-quote">$1</span>~gm;
      s~(?:\*{2}|\[b\])(.*?)(?:\*{2}|\[/b\])~<span class="markdown-bold">$1</span>~gs;
      s~(?:\*|\[i\])(.*?)(?:\*|\[/i\])~<span class="markdown-italic">$1</span>~gs;
      s~(?:\-\-|\[s\])(.*?)(?:\-\-|\[/s\])~<span class="markdown-strike">$1</span>~gs;
      s~(?:__|\[u\])(.*?)(?:__|\[/u\])~<span class="markdown-underlined">$1</span>~gs;
      s~(?:\[spoiler\]|%%)(.*?)(?:\[/spoiler\]|%%)~<span class="markdown-spoiler">$1</span>~gs;

      # Возвращаем блоки кода и добавляем подсветку
      s~\[code(?:\=(.*?))?\]\s*\[/code\]~"<pre class='".lc($1 || "")."'><code>".(shift @code)."</code></pre>"~gmse;

      # Смайлы
      s~:(?:coolface|hitriy):~<img src="/smilies/coolface.gif" alt="alt"/>~g;
      s~:trollface:~<img src="/smilies/trollface.gif" alt="alt"/>~g;
      s~:(?:nyan|kot):~<img src="/smilies/nyan.gif" alt="alt"/>~g;
      s~:(?:yoba|peka):~<img src="/smilies/yoba.png" alt="alt"/>~g;
      s~:(?:petro|shutka):~<img src="/smilies/petro.png" alt="alt"/>~g;
      s~:coola:~<img src="/smilies/coola.gif" alt="alt"/>~g;
      s~:troola:~<img src="/smilies/troola.gif" alt="alt"/>~g;
      s~:smith?:~<img src="/smilies/smit.png" alt="alt"/>~g;
      s~:mocha:~<img src="/smilies/mocha.png" alt="alt"/>~g;
      s~:(?:muha|mooha):~<img src="/smilies/muha.png" alt="alt"/>~g;
      s~:(?:rage|zloy):~<img src="/smilies/rage.png" alt="alt"/>~g;
      s~:(?:sobak|pes):~<img src="/smilies/sobak.gif" alt="alt"/>~g;
      s~:(?:okay|ladno):~<img src="/smilies/okay.png" alt="alt"/>~g;
      s~:(?:petuh|kudah):~<img src="/smilies/ochkopetuh.png" alt="alt"/>~g;
      s~:petuh2:~<img src="/smilies/ochkopetuh2.png" alt="alt"/>~g;
   }

   return;
}

sub save_file($$)
{
   my $self = shift;
   my($board, $upload) = @_;

   my $suff = get_file_suffix $upload->filename;
   my $fname = time . substr(rand, -4) . ".$suff";

   my $thumbsize = $self->db_boards->find_one(
      { name => $board }
   )->{options}->{thumbsize};

   my $image_dir  = $self->app->home->rel_dir(catdir("public", "img", $board));
   my $thumb_dir  = $self->app->home->rel_dir(catdir("public", "img", $board, "thumb"));
   my $image_path = catfile($image_dir, $fname);
   my $thumb_path = catfile($thumb_dir, $fname);

   mkpath $thumb_dir;

   $upload->move_to($image_path);
   return ($fname, $self->make_thumbnail($image_path, $thumb_path, $thumbsize));
}

sub make_thumbnail($$$)
{
   my $self = shift;
   my($image_path, $thumb_path, $thumbsize) = @_;

   my $im = new Image::Magick;
   map { warn $_ if $_ } $im->Read($image_path);

   my($width, $height) = $im->Get("width", "height");
   my($thumb_width, $thumb_height) = ($width, $height);

   if($width > $thumbsize || $height > $thumbsize)
   {
      if($width > $thumbsize)
      {
         $thumb_width  = $thumbsize;
         $thumb_height = int $height / ($width / $thumbsize);
      }

      if($thumb_height > $thumbsize)
      {
         my $tmp = $thumb_height / $thumbsize;
         $thumb_height = $thumbsize;
         $thumb_width = int $thumb_height / $tmp;
      }
   }

   map { warn $_ if $_ } $im->Scale(width => $thumb_width, height => $thumb_height);
   map { warn $_ if $_ } $im->Write(filename => $thumb_path, quality => 70);

   return ($width, $height, $thumb_width, $thumb_height);
}

sub delete_board($)
{
   my $self = shift;
   my($board) = @_;

   # Достаём данные из БД
   my $boards_collection = $self->db_boards;
   my $posts_collection  = $self->db_posts;

   # Удаление доски
   $boards_collection->remove({ name => $board });

   # Удаление тредов
   $self->delete_post($board, $_) for map {
      $_->{number}
   } $posts_collection->find(
      { board => $board, parent => 0 }
   )->fields(
      { number => 1 }
   )->all;

   return;
}

sub delete_post($$)
{
   my $self = shift;
   my($board, $post) = @_;

   # Вытаскиваем данные из БД
   my $posts_collection  = $self->db_posts;

   # Данные по посту
   my $post_data = $posts_collection->find_one(
      { board => $board, number => int $post }
   );

   # Если это пост в треде, уменьшаем количество постов в нём
   if($post_data->{parent})
   {
      $posts_collection->update(
         { board => $board, number => int $post_data->{parent} },
         { '$inc' => { posts_count => -1 } }
      );
   }
   # Если это тред, рекурсивно удаляем все посты в нём
   else
   {
      my @numbers = map { $_->{number} } grep { $_ } $posts_collection->find(
         { board => $board, parent => int $post_data->{number} }
      )->all;

      $self->delete_post($board, $_) for @numbers;
   }

   # Удаление поста
   $posts_collection->remove(
      { board => $board, number => int $post }
   );

   # Удаление картинок
   for my $image (@{ $post_data->{images} })
   {
      unlink $self->app->home->rel_file(catfile("public", "img", $board, $image->{fname}));
      unlink $self->app->home->rel_file(catfile("public", "img", $board, "thumb", $image->{fname}));
   }

   return;
}

sub delete_posts_by_ip($$)
{
   my $self = shift;
   my($board, $post) = @_;

   # Вытаскиваем данные из БД
   my $posts_collection  = $self->db_posts;

   # Данные по посту
   my $post_data = $posts_collection->find_one({ board => $board, number => int $post });

   # Удаляем все посты по айпи
   $self->delete_post($board, $_) for map {
      $_->{number}
   } $posts_collection->find(
      { board => $board, ip => $post_data->{ip} }
   )->all;

   return;
}

#----------------------------------------
# Капча
#----------------------------------------

sub make_captcha($)
{
   my $self = shift;
   my($ip) = @_;

   # state $chars = [split //, "АВГЕИКЛМНОПРСТУФЦЧШЫЯ"];
   state $chars = [split //, "0123456789"];

   srand(time);
   my $captcha;
   $captcha .= $chars->[rand @$chars] for 1 .. 2;

   my $db = $self->db_captcha;
   $db->remove({ _id => $ip });
   $db->insert({ _id => $ip, captcha => $captcha });

   write_file(
      $self->app->home->rel_file(catfile("captcha", "$ip.png")),
      { binmode => ":raw" },
      $self->captcha($captcha),
   );

   return $captcha;
}

sub remove_captcha($)
{
   my $self = shift;
   my($ip) = @_;

   my $db = $self->db_captcha;
   my $captcha = $db->find_one({ _id => $ip })->{captcha};
   $db->remove({ _id => $ip });

   unlink $self->app->home->rel_file(catfile("captcha", "$ip.png"));

   return $captcha;
}

sub get_captcha($)
{
   my $self = shift;
   my($ip) = @_;

   return $self->db_captcha->find_one({ _id => $ip })->{captcha};
}

sub check_captcha($$)
{
   my $self = shift;
   my($ip, $captcha) = @_;

   return $self->db_captcha->find_one({ _id => $ip })->{captcha} eq $captcha;
}

sub check_captcha_exists($$)
{
   my $self = shift;
   my($ip, $captcha) = @_;

   return !!$self->db_captcha->find_one({ _id => $ip });
}

#----------------------------------------
# Модераторы
#----------------------------------------

sub create_moderator($$)
{
   my $self = shift;

   my($board, $pass) = @_;

   my $mods_collection = $self->db_mods;

   unless($self->check_moderator_exists($pass))
   {
      $mods_collection->insert({password => $pass, boards => [$board]});
   }
   else
   {
      my $boards = $mods_collection->find({password => $pass})->next->{boards};
      $mods_collection->update({password => $pass}, {'$push' => {boards => $board}});
   }

   return;
}

sub remove_moderator($)
{
   my $self = shift;

   my($pass) = @_;

   my $mods_collection = $self->db_mods;
   $mods_collection->remove({ password => $pass });

   return;
}

sub check_moderator_exists($)
{
   my $self = shift;

   my($pass) = @_;

   my $mods_collection = $self->db_mods;
   return !!$mods_collection->find_one({ password => $pass} );
}

sub check_moderator_board($;$)
{
   my $self = shift;
   my($board, $pass) = @_;

   $pass = $self->session("mod")
      unless length $pass;

   return unless length $board && length $pass;
   return unless $self->check_moderator_exists($pass);

   my $mods_collection = $self->db_mods;
   return $board ~~ $mods_collection->find_one({ password => $pass })->{boards};
}

#----------------------------------------
# Баны
#----------------------------------------

sub ban_poster($$)
{
   my $self = shift;
   my($board, $post) = @_;

   $self->ban_ip(
      $self->db_posts->find_one(
         { board => $board, number => int $post }
      )->{ip}
   );

   return;
}

sub ban_ip($)
{
   my $self = shift;
   my($ip) = @_;

   $self->db_banlist->insert({ _id => $ip })
      unless $self->check_ban($ip);

   return;
}

sub unban_ip($)
{
   my $self = shift;
   my($ip) = @_;

   $self->db_banlist->remove({ _id => $ip });

   return;
}

sub check_ban($)
{
   my $self = shift;
   my($ip) = @_;

   return !!$self->db_banlist->find_one({ _id => $ip });
}

#----------------------------------------
# Разные проверки
#----------------------------------------

sub check_board_exists($)
{
   my $self = shift;
   my($board) = @_;

   return !!$self->db_boards->find_one({ name => $board });
}

sub check_thread_exists($$)
{
   my $self = shift;
   my($board, $thread) = @_;

   return !!$self->db_posts->find_one(
      { board => $board, number => int $thread, parent => 0 }
   );
}

sub check_post_exists($$)
{
   my $self = shift;
   my($board, $post) = @_;

   return !!$self->db_posts->find_one(
      { board => $board, number => int $post }
   );
}

sub check_file_type_allowed($$)
{
   my $self = shift;
   my($board, $type) = @_;

   return $type ~~ $self->db_boards->find_one(
      { name => $board }
   )->{options}->{formats};
}

sub check_file_size_allowed($$)
{
   my $self = shift;
   my($board, $size) = @_;

   return $size <= $self->db_boards->find_one(
      { name => $board }
   )->{options}->{maxlength};
}

sub check_blacklist($)
{
   my $self = shift;
   my($text) = @_;

   state $file = read_file(
      $self->app->home->rel_file("public/spam.txt"),
      binmode => ":utf8",
   );
   state $blacklist = [ grep { !/^#/ } split /\n\s*/, $file ];

   map { return 1 if $text =~ /$_/i } @$blacklist;
   return;
}

sub check_admin($)
{
   my $self = shift;
   my($pass) = @_;

   $pass = $self->session("admin_password")
      unless defined $pass;

   return unless defined $pass;
   return $pass eq $self->config->{admin_password};
}

#----------------------------------------
# Прочее
#----------------------------------------

sub get_boards_list
{
   my $self = shift;

   my $boards_collection = $self->db_boards;

   return [map {
      [ $_->{name}, $_->{title} ]
   } $boards_collection->find->fields(
      { name => 1, title => 1 }
   )->all];
}

sub render_error($)
{
   my $self = shift;

   my($message) = @_;

   $self->render(
      template => "pages/error",
      message  => $message,
   );
}

sub get_ip_country($)
{
   my $self = shift;
   my($ip) = @_;

   my $country = $self->geo($ip)->{CountryCode};
   return "" unless $country;
   $country = "Unknown" if $country == -1;

   return $country;
}

sub count_posts_by_board($)
{
   my $self = shift;
   my($board) = @_;

   my $posts_collection = $self->db_posts;

   my $threads = $posts_collection->find({ board => $board, parent => 0 })->count;
   my $posts   = $posts_collection->find({ board => $board })->count;

   return($threads, max(0, $posts - $threads));
}

2;
