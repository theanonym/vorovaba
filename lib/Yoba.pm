package Yoba;

use 5.010;
use strict;
use warnings;
use experimental qw/smartmatch switch/;
use utf8;
use Carp;

use base "Exporter";
our @EXPORT = qw/
   dirname basename mkpath rmtree catfile catdir
   read_file write_file
   time2str colored dump encode decode ceil floor
   max min sum

   html_escape remove_spaces full_escape
   get_file_suffix count_substring yoba_omitted
   yoba_posts
/;
our @EXPORT_OK = @EXPORT;

use File::Basename qw/dirname basename/;
use File::Path qw/mkpath rmtree/;
use File::Spec::Functions qw/catfile catdir/;
use File::Slurp qw/read_file write_file/;
use Date::Format qw/time2str/;
use Term::ANSIColor qw/colored/;
use Data::Dump qw/dump/;
use Encode qw/encode decode/;
use POSIX qw/ceil floor/;
use List::Util qw/max min sum/;
use Data::Dump qw/dump/;

sub html_escape($)
{
   my($str) = @_;
   return "" unless length $str;

   for($str)
   {
      # html
      s~&~&amp;~g;   # &
      s~<~&lt;~g;    # <
      s~>~&gt;~g;    # >
      s~"~&quot;~g;  # "
      s~'~&#39;~g;   # '

      # perl
      s~\$~&#36;~g;  # $
      s~@~&#64;~g;   # @
#     s~%~&#37;~g;   # %
      s~\{~&#123;~g; # {
      s~\}~&#125;~g; # }
   }

   return $str;
}

sub remove_spaces($)
{
   my($str) = @_;
   return "" unless length $str;

   for($str)
   {
      s~^\s+|\s+$~~g;
      s~\s+~ ~g;
   }

   return $str;
}

sub full_escape($)
{
   my($str) = @_;

   return remove_spaces html_escape $str;
}

sub get_file_suffix($)
{
   my($fname) = @_;

   my($suff) = map { lc } $fname =~ /\.(.{3,4})$/;
   $suff = "jpg" if $suff eq "jpeg";

   return $suff || "";
}

sub count_substring($$)
{
   my($str, $substr) = @_;

   return scalar @{[$str =~ /$substr/g]};
}

sub yoba_omitted($)
{
   my($n) = @_;

   given(substr($n, -1))
   {
      when([1])       { return "е" }
      when([2, 3, 4]) { return "я" }
      default         { return "й" }
   }
}

sub yoba_posts($)
{
   my($n) = @_;

   return "ов" if $n ~~ [11, 12, 13, 14];

   given(substr($n, -1))
   {
      when([1])       { return "" }
      when([2, 3, 4]) { return "а" }
      default         { return "ов" }
   }
}

2;
