package Mojolicious::Plugin::YobaCaptcha;

use 5.010;
use strict;
use warnings;
use utf8;
use Carp;

use base 'Mojolicious::Plugin';

use Image::Magick;

use Yoba;

sub register
{
   my($self, $app, $opt) = @_;

   $opt = {
      color   => "black",
      bgcolor => "white",
      size    => 20,
      wave_amplitude => 7,
      wave_length    => 80,
      %$opt,
   };

   $app->renderer->add_helper(
      captcha => sub {
         my ($self, $text) = @_;

         my $img = new Image::Magick(size => "400x400", magick => "png");
         map { $_ && warn $_ } $img->Read("gradient:#ffffff-#ffffff");

         map { $_ && warn $_ } $img->Annotate(
            pointsize   => $opt->{"size"},
            fill        => $opt->{"color"},
            text        => $text,
            geometry    => "+0+$opt->{size}",
         );

         map { $_ && warn $_ } $img->Wave(
            amplitude => $opt->{"wave_amplitude"},
            wavelength => $opt->{"wave_length"}
         );
         
         map { $_ && warn $_ } $img->Trim;

         #my $w = $img->Get("width");
         #my $h = $img->Get("height");

         #for(1 .. 50)
         #{
            #my $x = int rand $w;
            #my $y = int rand $h;

            #$img->Set("pixel[$x,$y]" => "gray");
         #}

         my $data;
         {
            my $fh = File::Temp->new(
               UNLINK => 1,
               DIR => $ENV{MOJO_TMPDIR} || File::Spec->tmpdir
            );
            map { $_ && warn $_ } $img->Write("png:" . $fh->filename);
            open $fh, '<', $fh->filename;
            local $/;
            $data = <$fh>;
         }
         return $data;
      }
   );
}

2;
