##Установка

#### Зависимости
* Perl >= 5.10
* MongoDB
* Memcached
* ImageMagick

Debian/Ubuntu:
```bash
aptitude install mongodb memcached imagemagick
```

#### Модули Perl
* Mojolicious
* MongoDB
* Cache::Memcached::Fast
* Image::Magick
* File::Slurp

Debian/Ubuntu:
```bash
curl -L http://cpanmin.us | perl - App::cpanminus
cpanm Mojolicious MongoDB Cache::Memcached::Fast Image::Magick File::Slurp
```

##Настройка и запуск

####Движок
Все настройки движка располагаются в [vorovaba.conf](https://github.com/theanonym/vorovaba/blob/master/vorovaba.conf).

Встроенный сервер запускается скриптом `start.sh` и доступен по порту 8080, где его подхватывает nginx.

####Nginx
Готовый [nginx.conf](https://github.com/theanonym/vorovaba/blob/master/nginx.conf) лежит в репозитории, его надо закинуть в `/etc/nginx/` и загрузить командой `nginx -s reload`.

####MongoDB
[Установка](https://docs.mongodb.com/manual/administration/install-on-linux/#recommended)

**Последние версии MongoDB поддерживают только 64-битные системы.** Для 32-битной ставьте [версию 2.6](https://docs.mongodb.com/v2.6/administration/install-on-linux/).

##Модификация
HTML шаблоны лежат в [templates/pages](https://github.com/theanonym/vorovaba/blob/master/templates/pages) (.ep - embed perl), код обычно начинается с `%` либо `<%= ... %>` внутри строки. [Больше информации](http://mojolicious.org/perldoc/Mojo/Template)

Основной код располагается в [lib](https://github.com/theanonym/vorovaba/blob/master/lib). Для редактирования кода и шаблонов в реальном времени можно использовать сервер для разработки `morbo -l http://*:8080 vorovaba.pl`.

CSS и JS файлы лежат в [public](https://github.com/theanonym/vorovaba/blob/master/public).
