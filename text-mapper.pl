#!/usr/bin/env perl
# Copyright (C) 2009-2019  Alex Schroeder <alex@gnu.org>
#
# This program is free software: you can redistribute it and/or modify it under
# the terms of the GNU General Public License as published by the Free Software
# Foundation, either version 3 of the License, or (at your option) any later
# version.
#
# This program is distributed in the hope that it will be useful, but WITHOUT
# ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
# FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License along with
# this program. If not, see <http://www.gnu.org/licenses/>.

package main;
use Modern::Perl;

my $dx = 100;
my $dy = 100*sqrt(3);
my $debug;
my $log;
my $contrib;

sub url_encode {
  my $str = shift;
  return '' unless $str;
  utf8::encode($str); # turn to byte string
  my @letters = split(//, $str);
  my %safe = map {$_ => 1} ('a' .. 'z', 'A' .. 'Z', '0' .. '9', '-', '_', '.', '!', '~', '*', "'", '(', ')', '#');
  foreach my $letter (@letters) {
    $letter = sprintf("%%%02x", ord($letter)) unless $safe{$letter};
  }
  return join('', @letters);
}

package Point;

use Class::Struct;

struct Point => { x => '$', y => '$', };

sub equal {
  my ($self, $other) = @_;
  return $self->x == $other->x
      && $self->y == $other->y;
}

sub coordinates {
  my ($self, $precision) = @_;
  return $self->x, $self->y if wantarray;
  return $self->x . "," . $self->y;
}

package Line;

use Class::Struct;

struct Line => {
		id => '$',
		points => '@',
		type => '$',
		label => '$',
		map => 'Mapper',
	       };

sub compute_missing_points {
  my $self = shift;
  my $i = 0;
  my $current = $self->points($i++);
  my @result = ($current);
  while ($self->points($i)) {
    $current = $self->one_step($current, $self->points($i));
    push(@result, $current);
    $i++ if $current->equal($self->points($i));
  }

  return @result;
}

sub partway {
  my ($self, $from, $to, $q) = @_;
  my ($x1, $y1) = $self->pixels($from);
  my ($x2, $y2) = $self->pixels($to);
  $q ||= 1;
  return $x1 + ($x2 - $x1) * $q, $y1 + ($y2 - $y1) * $q if wantarray;
  return sprintf("%.1f,%.1f", $x1 + ($x2 - $x1) * $q, $y1 + ($y2 - $y1) * $q);
}

sub svg {
  my $self = shift;
  my ($path, $current, $next, $closed);

  my @points = $self->compute_missing_points();
  if ($points[0]->equal($points[$#points])) {
    $closed = 1;
  }

  if ($closed) {
    for my $i (0 .. $#points - 1) {
      $current = $points[$i];
      $next = $points[$i+1];
      if (!$path) {
	my $a = $self->partway($current, $next, 0.3);
	my $b = $self->partway($current, $next, 0.5);
	my $c = $self->partway($points[$#points-1], $current, 0.7);
	my $d = $self->partway($points[$#points-1], $current, 0.5);
	$path = "M$d C$c $a $b";
      } else {
	# continue curve
	my $a = $self->partway($current, $next, 0.3);
	my $b = $self->partway($current, $next, 0.5);
	$path .= " S$a $b";
      }
    }
  } else {
    for my $i (0 .. $#points - 1) {
      $current = $points[$i];
      $next = $points[$i+1];
      if (!$path) {
	# line from a to b; control point a required for following S commands
	my $a = $self->partway($current, $next, 0.3);
	my $b = $self->partway($current, $next, 0.5);
	$path = "M$a C$b $a $b";
      } else {
	# continue curve
	my $a = $self->partway($current, $next, 0.3);
	my $b = $self->partway($current, $next, 0.5);
	$path .= " S$a $b";
      }
    }
    # end with a little stub
    $path .= " L" . $self->partway($current, $next, 0.7);
  }

  my $id = $self->id;
  my $type = $self->type;
  my $attributes = $self->map->path_attributes($type);
  my $data = qq{    <path id="$id" $attributes d="$path"/>\n};
  $data .= $self->debug($closed) if $debug;
  return $data;
}

sub svg_label {
  my ($self) = @_;
  return '' unless defined $self->label;
  my $id = $self->id;
  my $label = $self->label;
  my $attributes = $self->map->label_attributes || "";
  my $glow = $self->map->glow_attributes || "";
  my $url = $self->map->url;
  $url =~ s/\%s/url_encode($self->label)/e or $url .= url_encode($self->label) if $url;
  # default is left, but if the line goes from right to left, then "left" means "upside down"
  my $side = '';
  if ($self->points->[1]->x < $self->points->[0]->x
      or $#{$self->points} >= 2 and $self->points->[2]->x < $self->points->[0]->x) {
    $side = ' side="right"';
  }
  my $data = qq{    <g>\n};
  $data .= qq{      <text $attributes $glow><textPath$side href='#$id'>$label</textPath></text>\n>} if $glow;
  $data .= qq{      <a xlink:href="$url">} if $url;
  $data .= qq{      <text $attributes><textPath href='#$id'>$label</textPath></text>\n>};
  $data .= qq{      </a>} if $url;
  $data .= qq{    </g>\n};
  return $data;
}

sub debug {
  my ($self, $closed) = @_;
  my ($data, $current, $next);
  my @points = $self->compute_missing_points();
  for my $i (0 .. $#points - 1) {
    $current = $points[$i];
    $next = $points[$i+1];
    $data .= circle($self->pixels($current), 15, $i++);
    $data .= circle($self->partway($current, $next, 0.3), 3, 'a');
    $data .= circle($self->partway($current, $next, 0.5), 5, 'b');
    $data .= circle($self->partway($current, $next, 0.7), 3, 'c');
  }
  $data .= circle($self->pixels($next), 15, $#points);

  my ($x, $y) = $self->pixels($points[0]); $y += 30;
  $data .= "<text fill='#000' font-size='20pt' "
    . "text-anchor='middle' dominant-baseline='central' "
    . "x='$x' y='$y'>closed</text>"
      if $closed;

  return $data;
}

sub circle {
  my ($x, $y, $r, $i) = @_;
  my $data = "<circle fill='#666' cx='$x' cy='$y' r='$r'/>";
  $data .= "<text fill='#000' font-size='20pt' "
    . "text-anchor='middle' dominant-baseline='central' "
    . "x='$x' y='$y'>$i</text>" if $i;
  return "$data\n";
}

package Line::Hex;

use parent -norequire, 'Line';

sub pixels {
  my ($self, $point) = @_;
  my ($x, $y) = ($point->x * $dx * 3/2, $point->y * $dy - $point->x % 2 * $dy/2);
  return ($x, $y) if wantarray;
  return sprintf("%.1f,%.1f", $x, $y);
}

# Brute forcing the "next" step by trying all the neighbors. The
# connection data to connect to neighboring hexes.
#
# Example Map             Index for the array
#
#      0201                      2
#  0102    0302               1     3
#      0202    0402
#  0103    0303               6     4
#      0203    0403              5
#  0104    0304
#
#  Note that the arithmetic changes when x is odd.

sub one_step {
  my ($self, $from, $to) = @_;
  my $delta = [[[-1,  0], [ 0, -1], [+1,  0], [+1, +1], [ 0, +1], [-1, +1]],  # x is even
	       [[-1, -1], [ 0, -1], [+1, -1], [+1,  0], [ 0, +1], [-1,  0]]]; # x is odd
  my ($min, $best);
  for my $i (0 .. 5) {
    # make a new guess
    my ($x, $y) = ($from->x + $delta->[$from->x % 2]->[$i]->[0],
		   $from->y + $delta->[$from->x % 2]->[$i]->[1]);
    my $d = ($to->x - $x) * ($to->x - $x)
          + ($to->y - $y) * ($to->y - $y);
    if (!defined($min) || $d < $min) {
      $min = $d;
      $best = Point->new(x => $x, y => $y);
    }
  }
  return $best;
}

package Line::Square;

use parent -norequire, 'Line';

sub pixels {
  my ($self, $point) = @_;
  my ($x, $y) = ($point->x * $dy, $point->y * $dy);
  return ($x, $y) if wantarray;
  return sprintf("%d,%d", $x, $y);
}

sub one_step {
  my ($self, $from, $to) = @_;
  my ($min, $best);
  my $dx = $to->x - $from->x;
  my $dy = $to->y - $from->y;
  if (abs($dx) >= abs($dy)) {
    my $x = $from->x + ($dx > 0 ? 1 : -1);
    return Point->new(x => $x, y => $from->y);
  } else {
    my $y = $from->y + ($dy > 0 ? 1 : -1);
    return Point->new(x => $from->x, y => $y);
  }
}

package Hex;

use Class::Struct;

struct Hex => {
  x => '$',
  y => '$',
  type => '$',
  label => '$',
  size => '$',
  map => 'Mapper',
};

sub str {
  my $self = shift;
  return '(' . $self->x . ',' . $self->y . ')';
}

my @hex = ([-$dx, 0], [-$dx/2, $dy/2], [$dx/2, $dy/2],
	   [$dx, 0], [$dx/2, -$dy/2], [-$dx/2, -$dy/2]);

sub corners {
  return @hex;
}

sub svg_region {
  my ($self, $attributes) = @_;
  my $x = $self->x * $dx * 3/2;
  my $y = $self->y * $dy - $self->x % 2 * $dy/2;
  my $id = "hex" . $self->x . $self->y;
  my $points = join(" ", map {
    sprintf("%.1f,%.1f", $x + $_->[0], $y + $_->[1]) } $self->corners());
  return qq{    <polygon id="$id" $attributes points="$points" />\n}
}

sub svg {
  my $self = shift;
  my $x = $self->x;
  my $y = $self->y;
  my $data = '';
  for my $type (@{$self->type}) {
    $data .= sprintf(qq{    <use x="%.1f" y="%.1f" xlink:href="#%s" />\n},
		     $x * $dx * 3/2, $y * $dy - $x%2 * $dy/2, $type);
  }
  return $data;
}

sub svg_coordinates {
  my $self = shift;
  my $x = $self->x;
  my $y = $self->y;
  my $data = '';
  $data .= qq{    <text text-anchor="middle"};
  $data .= sprintf(qq{ x="%.1f" y="%.1f"},
		   $x * $dx * 3/2,
		   $y * $dy - $x%2 * $dy/2 - $dy * 0.4);
  $data .= ' ';
  $data .= $self->map->text_attributes || '';
  $data .= '>';
  $data .= sprintf(qq{%02d.%02d}, $x, $y);
  $data .= qq{</text>\n};
  return $data;
}

sub svg_label {
  my ($self, $url) = @_;
  return '' unless defined $self->label;
  my $attributes = $self->map->label_attributes;
  if ($self->size) {
    if (not $attributes =~ s/\bfont-size="\d+pt"/'font-size="' . $self->size . 'pt"'/e) {
      $attributes .= ' font-size="' . $self->size . '"';
    }
  }
  $url =~ s/\%s/url_encode($self->label)/e or $url .= url_encode($self->label) if $url;
  my $x = $self->x;
  my $y = $self->y;
  my $data = sprintf(qq{    <g><text text-anchor="middle" x="%.1f" y="%.1f" %s %s>}
                     . $self->label
                     . qq{</text>},
                     $x * $dx * 3/2, $y * $dy - $x%2 * $dy/2 + $dy * 0.4,
                     $attributes ||'',
		     $self->map->glow_attributes ||'');
  $data .= qq{<a xlink:href="$url">} if $url;
  $data .= sprintf(qq{<text text-anchor="middle" x="%.1f" y="%.1f" %s>}
		   . $self->label
		   . qq{</text>},
		   $x * $dx * 3/2, $y * $dy - $x%2 * $dy/2 + $dy * 0.4,
		   $attributes ||'');
  $data .= qq{</a>} if $url;
  $data .= qq{</g>\n};
  return $data;
}

package Square;

use Class::Struct;

struct Square => {
  x => '$',
  y => '$',
  type => '$',
  label => '$',
  size => '$',
  map => 'Mapper',
};

sub str {
  my $self = shift;
  return '(' . $self->x . ',' . $self->y . ')';
}

sub svg_region {
  my ($self, $attributes) = @_;
  my $x = ($self->x - 0.5) * $dy;
  my $y = ($self->y - 0.5) * $dy; # square!
  my $id = "square" . $self->x . $self->y;
  return qq{    <rect id="$id" $attributes x="$x" y="$y" width="$dy" height="$dy" />\n}
}

sub svg {
  my $self = shift;
  my $x = $self->x;
  my $y = $self->y;
  my $data = '';
  for my $type (@{$self->type}) {
    $data .= sprintf(qq{    <use x="%d" y="%d" xlink:href="#%s" />\n},
		     $x * $dy,
		     $y * $dy, # square
		     $type);
  }
  return $data;
}

sub svg_coordinates {
  my $self = shift;
  my $x = $self->x;
  my $y = $self->y;
  my $data = '';
  $data .= qq{    <text text-anchor="middle"};
  $data .= sprintf(qq{ x="%d" y="%d"},
		   $x * $dy,
		   ($y - 0.4) * $dy); # square
  $data .= ' ';
  $data .= $self->map->text_attributes || '';
  $data .= '>';
  $data .= sprintf(qq{%02d.%02d}, $x, $y);
  $data .= qq{</text>\n};
  return $data;
}

sub svg_label {
  my ($self, $url) = @_;
  return '' unless defined $self->label;
  my $attributes = $self->map->label_attributes;
  if ($self->size) {
    if (not $attributes =~ s/\bfont-size="\d+pt"/'font-size="' . $self->size . 'pt"'/e) {
      $attributes .= ' font-size="' . $self->size . '"';
    }
  }
  $url =~ s/\%s/url_encode($self->label)/e or $url .= url_encode($self->label) if $url;
  my $x = $self->x;
  my $y = $self->y;
  my $data = sprintf(qq{    <g><text text-anchor="middle" x="%d" y="%d" %s %s>}
                     . $self->label
                     . qq{</text>},
                     $x  * $dy,
		     ($y + 0.4) * $dy, # square
                     $attributes ||'',
		     $self->map->glow_attributes ||'');
  $data .= qq{<a xlink:href="$url">} if $url;
  $data .= sprintf(qq{<text text-anchor="middle" x="%d" y="%d" %s>}
		   . $self->label
		   . qq{</text>},
		   $x * $dy,
		   ($y + 0.4) * $dy, # square
		   $attributes ||'');
  $data .= qq{</a>} if $url;
  $data .= qq{</g>\n};
  return $data;
}

package Mapper;

use Class::Struct;
use LWP::UserAgent;

struct Mapper => {
		  regions => '@',
		  attributes => '%',
		  defs => '@',
		  map => '$',
		  path => '%',
		  lines => '@',
		  things => '@',
		  path_attributes => '%',
		  text_attributes => '$',
		  glow_attributes => '$',
		  label_attributes => '$',
		  messages => '@',
		  seen => '%',
		  license => '$',
		  other => '@',
		  url => '$',
		 };


sub example {
  return <<"EOT";
0101 mountain "mountain"
0102 swamp "swamp"
0103 hill "hill"
0104 forest "forest"
0201 empty pyramid "pyramid"
0202 tundra "tundra"
0203 coast "coast"
0204 empty house "house"
0301 woodland "woodland"
0302 wetland "wetland"
0303 plain "plain"
0304 sea "sea"
0401 hill tower "tower"
0402 sand house "house"
0403 jungle "jungle"
0502 sand "sand"
0205-0103-0202-0303-0402 road
0101-0203 river
0401-0303-0403 border
include $contrib/default.txt
license <text>Public Domain</text>
EOT
}

sub initialize {
  my ($self, $map) = @_;
  $self->map($map);
  $self->process(split(/\r?\n/, $map));
}

sub process {
  my $self = shift;
  my $line_id = 0;
  foreach (@_) {
    if (/^(\d\d)(\d\d)\s+(.*)/) {
      my $region = $self->make_region(x => $1, y => $2, map => $self);
      my $rest = $3;
      my ($label, $size) = $rest =~ /\"([^\"]+)\"\s*(\d+)?/;
      $region->label($label);
      $region->size($size);
      $rest =~ s/\"[^\"]+\"\s*\d*//; # strip label and size
      my @types = split(/\s+/, $rest);
      $region->type(\@types);
      push(@{$self->regions}, $region);
      push(@{$self->things}, $region);
    } elsif (/^(\d\d\d\d(?:-\d\d\d\d)+)\s+(\S+)\s*(?:"(.+)")?/) {
      my $line = $self->make_line(map => $self);
      $line->type($2);
      $line->label($3);
      $line->id('line' . $line_id++);
      my @points = map { my $point = Point->new(x => substr($_, 0, 2),
						y => substr($_, 2, 2));
		       } split(/-/, $1);
      $line->points(\@points);
      push(@{$self->lines}, $line);
    } elsif (/^(\S+)\s+attributes\s+(.*)/) {
      $self->attributes($1, $2);
    } elsif (/^(\S+)\s+lib\s+(.*)/) {
      $self->def(qq{<g id="$1">$2</g>});
    } elsif (/^(\S+)\s+xml\s+(.*)/) {
      $self->def(qq{<g id="$1">$2</g>});
    } elsif (/^(<.*>)/) {
      $self->def($1);
    } elsif (/^(\S+)\s+path\s+attributes\s+(.*)/) {
      $self->path_attributes($1, $2);
    } elsif (/^(\S+)\s+path\s+(.*)/) {
      $self->path($1, $2);
    } elsif (/^text\s+(.*)/) {
      $self->text_attributes($1);
    } elsif (/^glow\s+(.*)/) {
      $self->glow_attributes($1);
    } elsif (/^label\s+(.*)/) {
      $self->label_attributes($1);
    } elsif (/^license\s+(.*)/) {
      $self->license($1);
    } elsif (/^other\s+(.*)/) {
      push(@{$self->other()}, $1);
    } elsif (/^url\s+(\S+)/) {
      $self->url($1);
    } elsif (/^include\s+(\S*)/) {
      if (scalar keys %{$self->seen} > 5) {
	push(@{$self->messages},
	     "Includes are limited to five to prevent loops");
      } elsif (not $self->seen($1)) {
	$self->seen($1, 1);
	my $ua = LWP::UserAgent->new(ssl_opts => { verify_hostname => 1 });
	my $response = $ua->get($1);
	if ($response->is_success) {
	  $self->process(split(/\n/, $response->decoded_content));
	} else {
	  push(@{$self->messages}, $response->status_line);
	}
      }
    }
  }
  return $self;
}

sub def {
  my ($self, $svg) = @_;
  $svg =~ s/>\s+</></g;
  push(@{$self->defs}, $svg);
}

sub merge_attributes {
  my %attr = ();
  for my $attr (@_) {
    if ($attr) {
      while ($attr =~ /(\S+)=((["']).*?\3)/g) {
        $attr{$1} = $2;
      }
    }
  }
  return join(' ', map { $_ . '=' . $attr{$_} } sort keys %attr);
}

sub svg_header {
  my ($self) = @_;

  my $header = qq{<?xml version="1.0" encoding="UTF-8" standalone="no"?>
<svg xmlns="http://www.w3.org/2000/svg" version="1.1"
     xmlns:xlink="http://www.w3.org/1999/xlink"
};

  my ($minx, $miny, $maxx, $maxy);
  foreach my $region (@{$self->regions}) {
    $minx = $region->x if not defined($minx);
    $maxx = $region->x if not defined($maxx);
    $miny = $region->y if not defined($miny);
    $maxy = $region->y if not defined($maxy);
    $minx = $region->x if $minx > $region->x;
    $maxx = $region->x if $maxx < $region->x;
    $miny = $region->y if $miny > $region->y;
    $maxy = $region->y if $maxy < $region->y;
  }

  if (defined($minx) and defined($maxx) and defined($miny) and defined($maxy)) {

    my ($vx1, $vy1, $vx2, $vy2) = $self->viewbox($minx, $miny, $maxx, $maxy);
    my ($width, $height) = ($vx2 - $vx1, $vy2 - $vy1);

    $header .= qq{     viewBox="$vx1 $vy1 $width $height">\n};
    $header .= qq{     <!-- min ($minx, $miny), max ($maxx, $maxy) -->\n};
  } else {
    $header .= qq{>\n}; # something is seriously wrong, though!
  }
  return $header;
}

sub svg_defs {
  my ($self) = @_;
  # All the definitions are included by default.
  my $doc = "  <defs>\n";
  $doc .= "    " . join("\n    ", @{$self->defs}) if @{$self->defs};
  # collect region types from attributess and paths in case the sets don't overlap
  my %types = ();
  foreach my $region (@{$self->regions}) {
    foreach my $type (@{$region->type}) {
      $types{$type} = 1;
    }
  }
  foreach my $line (@{$self->lines}) {
    $types{$line->type} = 1;
  }
  # now go through them all
  foreach my $type (sort keys %types) {
    my $path = $self->path($type);
    my $attributes = merge_attributes($self->attributes($type));
    my $path_attributes = merge_attributes($self->path_attributes('default'),
					   $self->path_attributes($type));
    my $glow_attributes = $self->glow_attributes;
    if ($path || $attributes) {
      $doc .= qq{    <g id="$type">\n};
      # just shapes get a glow such, eg. a house (must come first)
      if ($path && !$attributes) {
	$doc .= qq{      <path $glow_attributes d='$path' />\n}
      }
      # region with attributes get a shape (square or hex), eg. plains and grass
      if ($attributes) {
	$doc .= "      " . $self->shape($attributes) . "\n";
      }
      # and now the attributes themselves the shape itself
      if ($path) {
      $doc .= qq{      <path $path_attributes d='$path' />\n}
      }
      # close
      $doc .= qq{    </g>\n};
    } else {
      # nothing
    }
  }
  $doc .= qq{  </defs>\n};
}

sub svg_backgrounds {
  my $self = shift;
  my $doc = qq{  <g id="backgrounds">\n};
  foreach my $thing (@{$self->things}) {
    # make a copy
    my @types = @{$thing->type};
    # keep attributes
    $thing->type([grep { $self->attributes($_) } @{$thing->type}]);
    $doc .= $thing->svg();
    # reset copy
    $thing->type(\@types);
  }
  $doc .= qq{  </g>\n};
  return $doc;
}

sub svg_things {
  my $self = shift;
  my $doc = qq{  <g id="things">\n};
  foreach my $thing (@{$self->things}) {
    # drop attributes
    $thing->type([grep { not $self->attributes($_) } @{$thing->type}]);
    $doc .= $thing->svg();
  }
  $doc .= qq{  </g>\n};
  return $doc;
}

sub svg_coordinates {
  my $self = shift;
  my $doc = qq{  <g id="coordinates">\n};
  foreach my $region (@{$self->regions}) {
    $doc .= $region->svg_coordinates();
  }
  $doc .= qq{  </g>\n};
  return $doc;
}

sub svg_lines {
  my $self = shift;
  my $doc = qq{  <g id="lines">\n};
  foreach my $line (@{$self->lines}) {
    $doc .= $line->svg();
  }
  $doc .= qq{  </g>\n};
  return $doc;
}

sub svg_regions {
  my ($self) = @_;
  my $doc = qq{  <g id="regions">\n};
  my $attributes = $self->attributes('default') || qq{fill="none"};
  foreach my $region (@{$self->regions}) {
    $doc .= $region->svg_region($attributes);
  }
  $doc .= qq{  </g>\n};
}

sub svg_line_labels {
  my $self = shift;
  my $doc = qq{  <g id="line_labels">\n};
  foreach my $line (@{$self->lines}) {
    $doc .= $line->svg_label();
  }
  $doc .= qq{  </g>\n};
  return $doc;
}

sub svg_labels {
  my $self = shift;
  my $doc = qq{  <g id="labels">\n};
  foreach my $region (@{$self->regions}) {
    $doc .= $region->svg_label($self->url);
  }
  $doc .= qq{  </g>\n};
  return $doc;
}

sub svg {
  my ($self) = @_;

  my $doc = $self->svg_header();
  $doc .= $self->svg_defs();
  $doc .= $self->svg_backgrounds(); # opaque backgrounds
  $doc .= $self->svg_lines();
  $doc .= $self->svg_things(); # icons, lines
  $doc .= $self->svg_coordinates();
  $doc .= $self->svg_regions();
  $doc .= $self->svg_line_labels();
  $doc .= $self->svg_labels();
  $doc .= $self->license() ||'';
  $doc .= join("\n", @{$self->other()}) . "\n";

  # error messages
  my $y = 10;
  foreach my $msg (@{$self->messages}) {
    $doc .= "  <text x='0' y='$y'>$msg</text>\n";
    $y += 10;
  }

  # source code
  $doc .= "<!-- Source\n" . $self->map() . "\n-->\n";
  $doc .= qq{</svg>\n};

  return $doc;
}

package Mapper::Hex;

use parent -norequire, 'Mapper';

sub make_region {
  my $self = shift;
  return Hex->new(@_);
}

sub make_line {
  my $self = shift;
  return Line::Hex->new(@_);
}

sub shape {
  my $self = shift;
  my $attributes = shift;
  my $points = join(" ", map {
    sprintf("%.1f,%.1f", $_->[0], $_->[1]) } Hex::corners());
  return qq{<polygon $attributes points='$points' />};
}

sub viewbox {
  my $self = shift;
  my ($minx, $miny, $maxx, $maxy) = @_;
  map { int($_) } ($minx * $dx * 3/2 - $dx - 60, ($miny - 1.0) * $dy - 50,
		   $maxx * $dx * 3/2 + $dx + 60, ($maxy + 0.5) * $dy + 100);
}

package Mapper::Square;

use parent -norequire, 'Mapper';

sub make_region {
  my $self = shift;
  return Square->new(@_);
}

sub make_line {
  my $self = shift;
  return Line::Square->new(@_);
}

sub shape {
  my $self = shift;
  my $attributes = shift;
  my $half = $dy / 2;
  return qq{<rect $attributes x="-$half" y="-$half" width="$dy" height="$dy" />};
}

sub viewbox {
  my $self = shift;
  my ($minx, $miny, $maxx, $maxy) = @_;
  map { int($_) } (($minx - 1) * $dy, ($miny - 1) * $dy,
		   ($maxx + 1) * $dy, ($maxy + 1) * $dy);
}

package Smale;

my %world = ();

#         ATLAS HEX PRIMARY TERRAIN TYPE
#         Water   Swamp   Desert  Plains  Forest  Hills   Mountains
# Water   P       W       W       W       W       W       -
# Swamp   W       P       -       W       W       -       -
# Desert  W       -       P       W       -       W       W
# Plains  S [1]   S       T       P [4]   S       T       -
# Forest  T [2]   T       -       S       P [5]   W [8]   T [11]
# Hills   W       -       S [3]   T       T [6]   P [9]   S
# Mountns -       -       W       -       W [7]   S [10]  P [12]
#
#  1. Treat as coastal (beach or scrub) if adjacent to water
#  2. 66% light forest
#  3. 33% rocky desert or high sand dunes
#  4. Treat as farmland in settled hexes
#  5. 33% heavy forest
#  6. 66% forested hills
#  7. 66% forested mountains
#  8. 33% forested hills
#  9. 20% canyon or fissure (not implemented)
# 10. 40% chance of a pass (not implemented)
# 11. 33% forested mountains
# 12. 20% chance of a dominating peak; 10% chance of a mountain pass (not
#     implemented); 5% volcano (not implemented)
#
# Notes
# water:    water
# sand:     sand or dust
# swamp:    dark-grey swamp (near trees) or dark-grey marshes (no trees)
# plains:   light-green grass, bush or bushes near water or forest
# forest:   green trees (light), green forest, dark-green forest (heavy);
#           use firs and fir-forest near hills or mountains
# hill:     light-grey hill, dust hill if sand dunes
# mountain: grey mountain, grey mountains (peak)

# later, grass land near a settlement might get the colors soil or dark-soil!

my %primary = ("water" =>  ["water"],
	       "swamp" =>  ["dark-grey swamp"],
	       "desert" => ["dust desert"],
	       "plains" => ["light-green grass"],
	       "forest" => ["green forest",
			    "green forest",
			    "dark-green fir-forest"],
	       "hill" =>   ["light-grey hill"],
	       "mountain" => ["grey mountain",
			      "grey mountain",
			      "grey mountain",
			      "grey mountain",
			      "grey mountains"]);

my %secondary = ("water" =>  ["light-green grass",
			      "light-green bush",
			      "light-green bushes"],
		 "swamp" =>  ["light-green grass"],
		 "desert" =>   ["light-grey hill",
				"light-grey hill",
				"dust hill"],
		 "plains" =>  ["green forest"],
		 "forest" => ["light-green grass",
			      "light-green bush"],
		 "hill" =>   ["grey mountain"],
		 "mountain" => ["light-grey hill"]);

my %tertiary = ("water" => ["green forest",
			    "green trees",
			    "green trees"],
		"swamp" => ["green forest"],
		"desert" => ["light-green grass"],
		"plains" => ["light-grey hill"],
		"forest" => ["light-grey forest-hill",
			     "light-grey forest-hill",
			     "light-grey hill"],
		"hill" => ["light-green grass"],
		"mountain" => ["green fir-forest",
			       "green forest",
			       "green forest-mountains"]);

my %wildcard = ("water" => ["dark-grey swamp",
			    "dark-grey marsh",
			    "sand desert",
			    "dust desert",
			    "light-grey hill",
			    "light-grey forest-hill"],
		"swamp" => ["water"],
		"desert" => ["water",
			     "grey mountain"],
		"plains" => ["water",
			     "dark-grey swamp",
			     "dust desert"],
		"forest" => ["water",
			     "water",
			     "water",
			     "dark-grey swamp",
			     "dark-grey swamp",
			     "dark-grey marsh",
			     "grey mountain",
			     "grey forest-mountain",
			     "grey forest-mountains"],
		"hill" => ["water",
			   "water",
			   "water",
			   "sand desert",
			   "sand desert",
			   "dust desert",
			   "green forest",
			   "green forest",
			   "green forest-hill"],
		"mountain" => ["sand desert",
			       "dust desert"]);


my %reverse_lookup = (
  # primary
  "water" => "water",
  "dark-grey swamp" => "swamp",
  "dust desert" => "desert",
  "light-green grass" => "plains",
  "green forest" => "forest",
  "dark-green fir-forest" => "forest",
  "light-grey hill" => "hill",
  "grey mountain" => "mountain",
  "grey mountains" => "mountain",
  # secondary
  "light-green bush" => "plains",
  "light-green bushes" => "plains",
  "dust hill" => "hill",
  # tertiary
  "green trees" => "forest",
  "light-grey forest-hill" => "hill",
  "green fir-forest" => "forest",
  "green forest-mountains" => "forest",
  # wildcard
  "dark-grey marsh" => "swamp",
  "sand desert" => "desert",
  "grey forest-mountain" => "mountain",
  "grey forest-mountains" => "mountain",
  "green forest-hill" => "forest",
  # code
  "light-soil fields" => "plains",
  "soil fields" => "plains",
    );

my %encounters = ("settlement" => ["thorp", "thorp", "thorp", "thorp",
				   "village",
				   "town", "town",
				   "large-town",
				   "city"],
		  "fortress" => ["keep", "tower", "castle"],
		  "religious" => ["shrine", "law", "chaos"],
		  "ruin" => [],
		  "monster" => [],
		  "natural" => []);

my @needs_fields;

sub one {
  my @arr = @_;
  @arr = @{$arr[0]} if @arr == 1 and ref $arr[0] eq 'ARRAY';
  return $arr[int(rand(scalar @arr))];
}

sub member {
  my $element = shift;
  foreach (@_) {
    return 1 if $element eq $_;
  }
}

sub verbose {
  $log->info(shift);
}

sub place_major {
  my ($x, $y, $encounter) = @_;
  my $thing = one(@{$encounters{$encounter}});
  return unless $thing;
  verbose("placing $thing ($encounter) at ($x,$y)");
  my $hex = one(full_hexes($x, $y));
  $x += $hex->[0];
  $y += $hex->[1];
  my $coordinates = sprintf("%02d%02d", $x, $y);
  my $primary = $reverse_lookup{$world{$coordinates}};
  my ($color, $terrain) = split(' ', $world{$coordinates}, 2);
  if ($encounter eq 'settlement') {
    if ($primary eq 'plains') {
      $color = one('light-soil', 'soil');
      verbose(" " . $world{$coordinates} . " is $primary and was changed to $color");
    }
    if ($primary ne 'plains' or member($thing, 'large-town', 'city')) {
      push(@needs_fields, [$x, $y]);
    }
  }
  # ignore $terrain for the moment and replace it with $thing
  $world{$coordinates} = "$color $thing";
}

sub populate_region {
  my ($hex, $primary) = @_;
  my $random = rand 100;
  if ($primary eq 'water' and $random < 10
      or $primary eq 'swamp' and $random < 20
      or $primary eq 'sand' and $random < 20
      or $primary eq 'grass' and $random < 60
      or $primary eq 'forest' and $random < 40
      or $primary eq 'hill' and $random < 40
      or $primary eq 'mountain' and $random < 20) {
    place_major($hex->[0], $hex->[1], one(keys %encounters));
  }
}

# Brute forcing by picking random sub hexes until we found an
# unassigned one.

sub pick_unassigned {
  my ($x, $y, @region) = @_;
  my $hex = one(@region);
  my $coordinates = sprintf("%02d%02d", $x + $hex->[0], $y + $hex->[1]);
  while ($world{$coordinates}) {
    $hex = one(@region);
    $coordinates = sprintf("%02d%02d", $x + $hex->[0], $y + $hex->[1]);
  }
  return $coordinates;
}

sub pick_remaining {
  my ($x, $y, @region) = @_;
  my @coordinates = ();
  for my $hex (@region) {
    my $coordinates = sprintf("%02d%02d", $x + $hex->[0], $y + $hex->[1]);
    push(@coordinates, $coordinates) unless $world{$coordinates};
  }
  return @coordinates;
}

# Precomputed for speed

sub full_hexes {
  my ($x, $y) = @_;
  if ($x % 2) {
    return ([0, -2],
	    [-2, -1], [-1, -1], [0, -1], [1, -1], [2, -1],
	    [-2,  0], [-1,  0], [0,  0], [1,  0], [2,  0],
	    [-2,  1], [-1,  1], [0,  1], [1,  1], [2,  1],
	    [-1,  2], [0,  2], [1,  2]);
  } else {
    return ([-1, -2], [0, -2], [1, -2],
	    [-2, -1], [-1, -1], [0, -1], [1, -1], [2, -1],
	    [-2,  0], [-1,  0], [0,  0], [1,  0], [2,  0],
            [-2,  1], [-1,  1], [0,  1], [1,  1], [2,  1],
	    [0,  2]);
  }
}

sub half_hexes {
  my ($x, $y) = @_;
  if ($x % 2) {
    return ([-2, -2], [-1, -2], [1, -2], [2, -2],
	    [-3,  0], [3,  0],
	    [-3,  1], [3,  1],
	    [-2,  2], [2,  2],
	    [-1,  3], [1,  3]);
  } else {
    return ([-1, -3], [1, -3],
	    [-2, -2], [2, -2],
	    [-3, -1], [3, -1],
	    [-3,  0], [3,  0],
	    [-2,  2], [-1,  2], [1,  2], [2,  2]);
  }
}

sub generate_region {
  my ($x, $y, $primary) = @_;
  $world{sprintf("%02d%02d", $x, $y)} = one($primary{$primary});

  my @region = full_hexes($x, $y);
  my $terrain;

  for (1..9) {
    my $coordinates = pick_unassigned($x, $y, @region);
    $terrain = one($primary{$primary});
    verbose(" primary   $coordinates => $terrain");
    $world{$coordinates} = $terrain;
  }

  for (1..6) {
    my $coordinates = pick_unassigned($x, $y, @region);
    $terrain =  one($secondary{$primary});
    verbose(" secondary $coordinates => $terrain");
    $world{$coordinates} = $terrain;
  }

  for my $coordinates (pick_remaining($x, $y, @region)) {
    if (rand > 0.1) {
      $terrain = one($tertiary{$primary});
      verbose(" tertiary  $coordinates => $terrain");
    } else {
      $terrain = one($wildcard{$primary});
      verbose(" wildcard  $coordinates => $terrain");
    }
    $world{$coordinates} = $terrain;
  }

  for my $coordinates (pick_remaining($x, $y, half_hexes($x, $y))) {
    my $random = rand 6;
    if ($random < 3) {
      $terrain = one($primary{$primary});
      verbose("  halfhex primary   $coordinates => $terrain");
    } elsif ($random < 5) {
      $terrain = one($secondary{$primary});
      verbose("  halfhex secondary $coordinates => $terrain");
    } else {
      $terrain = one($tertiary{$primary});
      verbose("  halfhex tertiary  $coordinates => $terrain");
    }
    $world{$coordinates} = $terrain;
  }
}

sub seed_region {
  my ($seeds, $terrain) = @_;
  my $terrain_above;
  for my $hex (@$seeds) {
    verbose("seed_region (" . $hex->[0] . "," . $hex->[1] . ") with $terrain");
    generate_region($hex->[0], $hex->[1], $terrain);
    populate_region($hex, $terrain);
    my $random = rand 12;
    # pick next terrain based on the previous one (to the left); or the one
    # above if in the first column
    my $next;
    $terrain = $terrain_above if $hex->[0] == 1 and $terrain_above;
    if ($random < 6) {
      $next = one($primary{$terrain});
      verbose("picked primary $next");
    } elsif ($random < 9) {
      $next = one($secondary{$terrain});
      verbose("picked secondary $next");
    } elsif ($random < 11) {
      $next = one($tertiary{$terrain});
      verbose("picked tertiary $next");
    } else {
      $next = one($wildcard{$terrain});
      verbose("picked wildcard $next");
    }
    $terrain_above = $terrain if $hex->[0] == 1;
    die "Terrain lacks reverse_lookup: $next\n" unless $reverse_lookup{$next};
    $terrain = $reverse_lookup{$next};
  }
}

sub agriculture {
  for my $hex (@needs_fields) {
    verbose("looking to plant fields near " . sprintf("%02d%02d", $hex->[0], $hex->[1]));
    my $delta = [[[-1,  0], [ 0, -1], [+1,  0], [+1, +1], [ 0, +1], [-1, +1]],  # x is even
		 [[-1, -1], [ 0, -1], [+1, -1], [+1,  0], [ 0, +1], [-1,  0]]]; # x is odd
    my @plains;
    for my $i (0 .. 5) {
      my ($x, $y) = ($hex->[0] + $delta->[$hex->[0] % 2]->[$i]->[0],
		     $hex->[1] + $delta->[$hex->[0] % 2]->[$i]->[1]);
      my $coordinates = sprintf("%02d%02d", $x, $y);
      if ($world{$coordinates}) {
	my ($color, $terrain) = split(' ', $world{$coordinates}, 2);
	verbose("  $coordinates is " . $world{$coordinates} . " ie. " . $reverse_lookup{$world{$coordinates}});
	if ($reverse_lookup{$world{$coordinates}} eq 'plains') {
	  verbose("   $coordinates is a candidate");
	  push(@plains, $coordinates);
	}
      }
    }
    next unless @plains;
    my $target = one(@plains);
    $world{$target} = one('light-soil fields', 'soil fields');
    verbose(" $target planted with " . $world{$target});
  }
}

sub generate_map {
  my ($bw, $width, $height) = @_;
  $width = 20 if not defined $width or $width < 1 or $width > 100;
  $height = 10 if not defined $height or $height < 1 or $height > 100;

  my $seeds;
  for (my $y = 1; $y < $height + 2; $y += 5) {
    for (my $x = 1; $x < $width + 2; $x += 5) {
      # [1,1] [6,3], [11,1], [16,3]
      my $y0 = $y + int(($x % 10) / 3);
      push(@$seeds, [$x, $y0]);
    }
  }

  %world = (); # reinitialize!

  my @seed_terrain = keys %primary;
  seed_region($seeds, one(@seed_terrain));
  agriculture();

  # delete extra hexes we generated to fill the gaps
  for my $coordinates (keys %world) {
    $coordinates =~ /(..)(..)/;
    delete $world{$coordinates} if $1 < 1 or $2 < 1;
    delete $world{$coordinates} if $1 > $width or $2 > $height;
  }

  if ($bw) {
    for my $coordinates (keys %world) {
      my ($color, $rest) = split(' ', $world{$coordinates}, 2);
      if ($rest) {
	$world{$coordinates} = $rest;
      } else {
	delete $world{$coordinates};
      }
    }
  }

  return join("\n", map { $_ . " " . $world{$_} } sort keys %world) . "\n"
    . "include $contrib/gnomeyland.txt\n";
}

package Schroeder;
use Modern::Perl;
use List::Util 'shuffle';
use Class::Struct;

# Currently empty
struct Schroeder => {};

# We're assuming that $width and $height have two digits (10 <= n <= 99).

my $width;
my $height;
my $steepness;
my $peaks;
my $peak;
my $bumps;
my $bump;
my $bottom;
my $arid;

sub xy {
  my $self = shift;
  my $coordinates = shift;
  return (substr($coordinates, 0, 2), substr($coordinates, 2));
}

sub coordinates {
  my ($x, $y) = @_;
  return sprintf("%02d%02d", $x, $y);
}

sub legal {
  my $self = shift;
  my ($x, $y) = @_;
  ($x, $y) = $self->xy($x) if not defined $y;
  return @_ if $x > 0 and $x <= $width and $y > 0 and $y <= $height;
}

sub remove_closer_than {
  my $self = shift;
  my ($limit, @hexes) = @_;
  my @filtered;
 HEX:
  for my $hex (@hexes) {
    my ($x1, $y1) = $self->xy($hex);
    # check distances with all the hexes already in the list
    for my $existing (@filtered) {
      my ($x2, $y2) = $self->xy($existing);
      my $distance = $self->distance($x1, $y1, $x2, $y2);
      # warn "Distance between $x1$y1 and $x2$y2 is $distance\n";
      next HEX if $distance < $limit;
    }
    # if this hex wasn't skipped, it goes on to the list
    push(@filtered, $hex);
  }
  return @filtered;
}

sub flat {
  my $self = shift;
  # initialize the altitude map; this is required so that we have a list of
  # legal hex coordinates somewhere
  my ($altitude) = @_;
  for my $y (1 .. $height) {
    for my $x (1 .. $width) {
      my $coordinates = coordinates($x, $y);
      $altitude->{$coordinates} = 0;
    }
  }
}

sub place_peak {
  my $self = shift;
  my $altitude = shift;
  my $count = shift;
  my $current_altitude = shift;
  my @queue;
  # place some peaks and put them in a queue
  for (1 .. $count) {
    # try to find an empty hex
    for (1 .. 6) {
      my $x = int(rand($width)) + 1;
      my $y = int(rand($height)) + 1;
      my $coordinates = coordinates($x, $y);
      next if $altitude->{$coordinates};
      $altitude->{$coordinates} = $current_altitude;
      $log->debug("placed $current_altitude at $coordinates");
      push(@queue, $coordinates);
      last;
    }
  }
  return @queue;
}

sub grow_mountains {
  my $self = shift;
  my $altitude = shift;
  my @queue = @_;
  # go through the queue and add adjacent lower altitude hexes, if possible; the
  # hexes added are to the end of the queue
  while (@queue) {
    my $coordinates = shift @queue;
    my $current_altitude = $altitude->{$coordinates};
    next unless $current_altitude > 0;
    # pick some random neighbors based on variable steepness
    my $n = $steepness;
    # round up based on fraction
    $n += 1 if rand() < $n - int($n);
    $n = int($n);
    next if $n < 1;
    for (1 .. $n) {
      # try to find an empty neighbor; abort after six attempts
      for (1 .. 6) {
	my ($x, $y) = $self->neighbor($coordinates, $self->random_neighbor());
	next unless $self->legal($x, $y);
	my $other = coordinates($x, $y);
	# if this is taken, look further
	if ($altitude->{$other}) {
	  ($x, $y) = $self->neighbor2($coordinates, $self->random_neighbor2());
	  next unless $self->legal($x, $y);
	  $other = coordinates($x, $y);
	  # if this is also taken, try again
	  next if $altitude->{$other};
	}
	# if we found an empty neighbor, set its altitude
	$altitude->{$other} = $current_altitude > 0 ? $current_altitude - 1 : 0;
	push(@queue, $other);
	last;
      }
    }
  }
}

sub fix_altitude {
  my $self = shift;
  my $altitude = shift;
  # go through all the hexes
  for my $coordinates (sort keys %$altitude) {
    # find hexes that we missed and give them the height of a random neighbor
    if (not defined $altitude->{$coordinates}) {
      # warn "identified a hex that was skipped: $coordinates\n";
      # try to find a suitable neighbor
      for (1 .. 6) {
	my ($x, $y) = $self->neighbor($coordinates, $self->random_neighbor());
	next unless $self->legal($x, $y);
	my $other = coordinates($x, $y);
	next unless defined $altitude->{$other};
	$altitude->{$coordinates} = $altitude->{$other};
	last;
      }
      # if we didn't find one in the last six attempts, just make it hole in the ground
      if (not defined $altitude->{$coordinates}) {
	$altitude->{$coordinates} = 0;
      }
    }
  }
}

sub altitude {
  my $self = shift;
  my ($world, $altitude) = @_;
  my @queue = $self->place_peak($altitude, $peaks, $peak);
  $self->grow_mountains($altitude, @queue);
  $self->fix_altitude($altitude);
  # note height for debugging purposes
  for my $coordinates (sort keys %$altitude) {
    $world->{$coordinates} = "height$altitude->{$coordinates}";
  }
}

sub bumps {
  my $self = shift;
  my ($world, $altitude) = @_;
  for (1 .. $bumps) {
    for my $delta (-$bump, $bump) {
      # six attempts to try and find a good hex
      for (1 .. 6) {
	my $x = int(rand($width)) + 1;
	my $y = int(rand($height)) + 1;
	my $coordinates = coordinates($x, $y);
	my $current_altitude = $altitude->{$coordinates} + $delta;
	next if $current_altitude > 10 or $current_altitude < 0;
	# bump it up or down
	$altitude->{$coordinates} = $current_altitude;
	$world->{$coordinates} = "height$altitude->{$coordinates}";
	$log->debug("bumped altitude of $coordinates by $delta to $current_altitude");
	# if the bump was +2 or -2, bump the neighbours by +1 or -1
	if ($delta < -1 or $delta > 1) {
	  my $delta = $delta - $delta / abs($delta);
	  for my $i ($self->neighbors()) {
	    my ($x, $y) = $self->neighbor($coordinates, $i);
	    my $legal = $self->legal($x, $y);
	    my $other = coordinates($x, $y);
	    next if not $legal;
	    $current_altitude = $altitude->{$other} + $delta;
	    next if $current_altitude > 10 or $current_altitude < 0;
	    $altitude->{$other} = $current_altitude;
	    $world->{$other} = "height$altitude->{$other}";
	    $log->debug("$i bumped altitude of $other by $delta to $current_altitude");
	  }
	}
	# if we have found a good hex, don't go through all the other attempts
	last;
      }
    }
  }
}

sub water {
  my $self = shift;
  my ($world, $altitude, $water) = @_;
  # reset in case we run this twice
  # go through all the hexes
  for my $coordinates (sort keys %$altitude) {
    # note preferred water flow by identifying lower lying neighbors
    my ($lowest, $direction);
    # look at neighbors in random order
  NEIGHBOR:
    for my $i (shuffle $self->neighbors()) {
      my ($x, $y) = $self->neighbor($coordinates, $i);
      my $legal = $self->legal($x, $y);
      my $other = coordinates($x, $y);
      # my $debug = $coordinates eq "1004" && $other eq "0904";
      next if $legal and $altitude->{$other} > $altitude->{$coordinates};
      # don't point head on to another arrow
      next if $legal and $water->{$other} and $water->{$other} == ($i-3) % 6;
      # don't point into loops
      my %loop = ($coordinates => 1, $other => 1);
      my $next = $other;
      $log->debug("Loop detection starting with $coordinates and $other");
      while ($next) {
	# no water flow known is also good;
	$log->debug("water for $next: " . ($water->{$next} || "none"));
	last unless defined $water->{$next};
	($x, $y) = $self->neighbor($next, $water->{$next});
	# leaving the map is good
	$log->debug("legal for $next: " . $self->legal($x, $y));
	last unless $self->legal($x, $y);
	$next = coordinates($x, $y);
	# skip this neighbor if this is a loop
	$log->debug("is $next in a loop? " . ($loop{$next} || "no"));
	next NEIGHBOR if $loop{$next};
	$loop{$next} = 1;
      }
      if (not defined $direction
	  or not $legal and $altitude->{$coordinates} < $lowest
	  or $legal and $altitude->{$other} < $lowest) {
	$lowest = $legal ? $altitude->{$other} : $altitude->{$coordinates};
	$direction = $i;
	$log->debug("Set lowest to $lowest ($direction)");
      }
    }
    if (defined $direction) {
      $water->{$coordinates} = $direction;
      $world->{$coordinates} =~ s/arrow\d/arrow$water->{$coordinates}/
	  or $world->{$coordinates} .= " arrow$water->{$coordinates}";
    }
  }
}

sub mountains {
  my $self = shift;
  my ($world, $altitude) = @_;
  # place the types
  for my $coordinates (keys %$altitude) {
    if ($altitude->{$coordinates} >= 10) {
      $world->{$coordinates} = "white mountains";
    } elsif ($altitude->{$coordinates} >= 9) {
      $world->{$coordinates} = "white mountain";
    } elsif ($altitude->{$coordinates} >= 8) {
      $world->{$coordinates} = "light-grey mountain";
    }
  }
}

sub lakes {
  my $self = shift;
  my ($world, $altitude, $water) = @_;
  # any areas without water flow are lakes
  for my $coordinates (keys %$altitude) {
    if ($altitude->{$coordinates} <= $bottom
	or not defined $water->{$coordinates}) {
      $world->{$coordinates} = "water";
    }
  }
}

sub swamps {
  my $self = shift;
  # any area with water flowing to a neighbor at the same altitude is a swamp
  my ($world, $altitude, $water, $flow) = @_;
 HEX:
  for my $coordinates (keys %$altitude) {
    # don't turn lakes into swamps and skip bogs
    next if $world->{$coordinates} =~ /water|swamp/;
    # swamps require a river
    next unless $flow->{$coordinates};
    # look at the neighbor the water would flow to
    my ($x, $y) = $self->neighbor($coordinates, $water->{$coordinates});
    # skip if water flows off the map
    next unless $self->legal($x, $y);
    my $other = coordinates($x, $y);
    # skip if water flows downhill
    next if $altitude->{$coordinates} > $altitude->{$other};
    # if there was no lower neighbor, this is a swamp
    if ($altitude->{$coordinates} >= 6) {
      $world->{$coordinates} =~ s/height\d+/grey swamp/;
    } else {
      $world->{$coordinates} =~ s/height\d+/dark-grey swamp/;
    }
  }
}

sub direction {
  my $self = shift;
  my ($from, $to) = @_;
  for my $i ($self->neighbors()) {
    return $i if $to eq coordinates($self->neighbor($from, $i));
  }
}

sub flood {
  my $self = shift;
  my ($world, $altitude, $water) = @_;
  # backtracking information: $from = $flow{$to}
  my %flow;
  # allow easy skipping
  my %seen;
  # start with a list of hexes to look at; as always, keys is a source of
  # randomness that's independent of srand which is why we shuffle sort
  my @lakes = shuffle sort grep { not defined $water->{$_} } keys %$world;
  return unless @lakes;
  my $start = shift(@lakes);
  my @candidates = ($start);
  while (@candidates) {
    # Prefer candidates outside the map with altitude 0; reshuffle because
    # candidates at the same height are all equal and early or late discoveries
    # should not matter (not shuffling means it matters whether candidates are
    # pushed or unshifted because this is a stable sort)
    @candidates = sort {
      ($altitude->{$a}||0) <=> ($altitude->{$b}||0)
    } shuffle @candidates;
    $log->debug("Candidates @candidates");
    my $coordinates;
    do {
      $coordinates = shift(@candidates);
    } until not $coordinates or not $seen{$coordinates};
    last unless $coordinates;
    $seen{$coordinates} = 1;
    $log->debug("Looking at $coordinates");
    my ($x, $y) = $self->xy($coordinates);
    if ($self->legal($x, $y)) {
      # if we're still on the map, check all the unknown neighbors
      my $from = $coordinates;
      for my $i ($self->neighbors()) {
	my $to = coordinates($self->neighbor($from, $i));
	next if $seen{$to};
	$log->debug("Adding $to to our candidates");
	$flow{$to} = $from;
	# adding to the front as we keep pushing forward (I hope)
	push(@candidates, $to);
      }
      next;
    }
    $log->debug("We left the map at $coordinates");
    my $to = $coordinates;
    my $from = $flow{$to};
    while ($from) {
      my $i = $self->direction($from, $to);
      if (not defined $water->{$from}
	  or $water->{$from} != $i) {
	$log->debug("Arrow for $from now points to $to");
	$water->{$from} = $i;
	$world->{$from} =~ s/arrow\d/arrow$i/
	    or $world->{$from} .= " arrow$i";
      } else {
	$log->debug("Arrow for $from already points $to");
      }
      $to = $from;
      $from = $flow{$to};
    }
    # pick the next lake
    do {
      $start = shift(@lakes);
      $log->debug("Next lake is $start") if $start;
    } until not $start or not defined $water->{$start};
    last unless $start;
    %seen = %flow = ();
    @candidates = ($start);
  }
}

sub rivers {
  my $self = shift;
  my ($world, $altitude, $water, $flow, $level) = @_;
  # $flow are the sources points of rivers, or 1 if a river flows through them
  my @growing = map {
    $world->{$_} = "light-grey forest-hill" unless $world->{$_} =~ /mountain|swamp|water/;
    # warn "Started a river at $_ ($altitude->{$_} == $level)\n";
    $flow->{$_} = [$_]
  } sort grep {
    $altitude->{$_} == $level and not $flow->{$_}
  } keys %$altitude;
  return $self->grow_rivers(\@growing, $water, $flow);
}

sub grow_rivers {
  my $self = shift;
  my ($growing, $water, $flow) = @_;
  my @rivers;
  while (@$growing) {
    # warn "Rivers: " . @growing . "\n";
    # pick a random growing river and grow it
    my $n = int(rand(scalar @$growing));
    my $river = $growing->[$n];
    # warn "Picking @$river\n";
    my $coordinates = $river->[-1];
    my $end = 1;
    if (defined $water->{$coordinates}) {
      my $other = coordinates($self->neighbor($coordinates, $water->{$coordinates}));
      die "Adding $other leads to an infinite loop in river @$river\n" if grep /$other/, @$river;
      # if we flowed into a hex with a river
      if (ref $flow->{$other}) {
	# warn "Prepending @$river to @{$flow->{$other}}\n";
	# prepend the current river to the other river
	unshift(@{$flow->{$other}}, @$river);
	# move the source marker
	$flow->{$river->[0]} = $flow->{$other};
	$flow->{$other} = 1;
	# and remove the current river from the growing list
	splice(@$growing, $n, 1);
	# warn "Flow at $river->[0]: @{$flow->{$river->[0]}}\n";
	# warn "Flow at $other: $flow->{$other}\n";
      } else {
	$flow->{$coordinates} = 1;
	push(@$river, $other);
      }
    } else {
      # stop growing this river
      # warn "Stopped river: @$river\n" if grep(/0914/, @$river);
      push(@rivers, splice(@$growing, $n, 1));
    }
  }
  return @rivers;
}

sub canyons {
  my $self = shift;
  my ($world, $altitude, $rivers) = @_;
  my @canyons;
  # using a reference to an array so that we can leave pointers in the %seen hash
  my $canyon = [];
  # remember which canyon flows through which hex
  my %seen;
  for my $river (@$rivers) {
    my $last = $river->[0];
    my $current_altitude = $altitude->{$last};
    $log->debug("Looking at @$river ($current_altitude)");
    for my $coordinates (@$river) {
      $log->debug("Looking at $coordinates");
      if ($seen{$coordinates}) {
	# the rest of this river was already looked at, so there is no need to
	# do the rest of this river; if we're in a canyon, prepend it to the one
	# we just found before ending
	if (@$canyon) {
	  my @other = @{$seen{$coordinates}};
	  if ($other[0] eq $canyon->[-1]) {
	    $log->debug("Canyon @$canyon of river @$river merging with @other at $coordinates");
	    unshift(@{$seen{$coordinates}}, @$canyon[0 .. @$canyon - 2]);
	  } else {
	    $log->debug("Canyon @$canyon of river @$river stumbled upon existing canyon @other at $coordinates");
	    while (@other) {
	      my $other = shift(@other);
	      next if $other ne $coordinates;
	      push(@$canyon, $other, @other);
	      last;
	    }
	    $log->debug("Canyon @$canyon");
	    push(@canyons, $canyon);
	  }
	  $canyon = [];
	}
	$log->debug("We've seen the rest: @{$seen{$coordinates}}");
	last;
      }
      # no canyons through water!
      if ($altitude->{$coordinates} and $current_altitude < $altitude->{$coordinates}
	  and $world->{$coordinates} !~ /water/) {
	# river is digging a canyon; if this not the start of the river and it
	# is the start of a canyon, prepend the last step
	push(@$canyon, $last) unless @$canyon;
	push(@$canyon, $coordinates);
	$log->debug("Growing canyon @$canyon");
	$seen{$coordinates} = $canyon;
      } else {
	# if we just left a canyon, append the current step
	if (@$canyon) {
	  push(@$canyon, $coordinates);
	  push(@canyons, $canyon);
	  $log->debug("Looking at river @$river");
	  $log->debug("Canyon @$canyon");
	  $canyon = [];
	  last;
	}
	# not digging a canyon
	$last = $coordinates;
	$current_altitude = $altitude->{$coordinates};
      }
    }
  }
  return @canyons;
}

sub wet {
  my $self = shift;
  # a hex is wet if there is a river, a swamp or a forest within 2 hexes
  my ($coordinates, $world, $flow) = @_;
  for my $i ($self->neighbors()) {
    my ($x, $y) = $self->neighbor($coordinates, $i);
    # next unless $self->legal($x, $y);
    my $other = coordinates($x, $y);
    return 0 if $flow->{$other};
  }
  for my $i ($self->neighbors2()) {
    my ($x, $y) = $self->neighbor2($coordinates, $i);
    # next unless $self->legal($x, $y);
    my $other = coordinates($x, $y);
    return 0 if $flow->{$other};
  }
  return 1;
}

sub grow_forest {
  my $self = shift;
  my ($coordinates, $world, $altitude) = @_;
  my @candidates = ($coordinates);
  my $n = $arid;
  # fractions are allowed
  $n += 1 if rand() < $arid - int($arid);
  $n = int($n);
  $log->debug("Arid: $n");
  if ($n >= 1) {
    for my $i ($self->neighbors()) {
      my ($x, $y) = $self->neighbor($coordinates, $i);
      next unless $self->legal($x, $y);
      my $other = coordinates($x, $y);
      push(@candidates, $other) if $world->{$other} !~ /mountain|hill|water|swamp/;
    }
  }
  if ($n >= 2) {
    for my $i ($self->neighbors2()) {
      my ($x, $y) = $self->neighbor2($coordinates, $i);
      next unless $self->legal($x, $y);
      my $other = coordinates($x, $y);
      push(@candidates, $other) if $world->{$other} !~ /mountain|hill|water|swamp/;
    }
  }
  for $coordinates (@candidates) {
    if ($altitude->{$coordinates} >= 7) {
      $world->{$coordinates} = "light-green fir-forest";
    } elsif ($altitude->{$coordinates} >= 6) {
      $world->{$coordinates} = "green fir-forest";
    } elsif ($altitude->{$coordinates} >= 4) {
      $world->{$coordinates} = "green forest";
    } else {
      $world->{$coordinates} = "dark-green forest";
    }
  }
}

sub forests {
  my $self = shift;
  my ($world, $altitude, $flow) = @_;
  # empty hexes with a river flowing through them are forest filled valleys
  for my $coordinates (keys %$flow) {
    if ($world->{$coordinates} !~ /mountain|hill|water|swamp/) {
      $self->grow_forest($coordinates, $world, $altitude);
    }
  }
}

sub dry {
  my $self = shift;
  # a hex is dry if there is no river within 2 hexes of it
  my ($coordinates, $flow) = @_;
  for my $i ($self->neighbors()) {
    my ($x, $y) = $self->neighbor($coordinates, $i);
    # next unless $self->legal($x, $y);
    my $other = coordinates($x, $y);
    return 0 if $flow->{$other};
  }
  for my $i ($self->neighbors2()) {
    my ($x, $y) = $self->neighbor2($coordinates, $i);
    # next unless $self->legal($x, $y);
    my $other = coordinates($x, $y);
    return 0 if $flow->{$other};
  }
  return 1;
}

sub bogs {
  my $self = shift;
  my ($world, $altitude, $water, $flow) = @_;
 HEX:
  for my $coordinates (keys %$altitude) {
    # limit ourselves to altitude 7
    next if $altitude->{$coordinates} != 7;
    # don't turn lakes into bogs
    next if $world->{$coordinates} =~ /water/;
    # look at the neighbor the water would flow to
    my ($x, $y) = $self->neighbor($coordinates, $water->{$coordinates});
    # skip if water flows off the map
    next unless $self->legal($x, $y);
    my $other = coordinates($x, $y);
    # skip if water flows downhill
    next if $altitude->{$coordinates} > $altitude->{$other};
    # if there was no lower neighbor, this is a bog
    $world->{$coordinates} =~ s/height\d+/grey swamp/;
  }
}

sub bushes {
  my $self = shift;
  my ($world, $altitude, $water, $flow) = @_;
  # as always, keys is a source of randomness that's independent of srand which
  # is why we sort
  for my $coordinates (sort keys %$world) {
    if ($world->{$coordinates} !~ /mountain|hill|water|swamp|forest|firs|trees/) {
      my $thing = "bushes";
      my $rand = rand();
      if ($altitude->{$coordinates} >= 3 and $rand < 0.2) {
	$thing = "hill";
      } elsif ($altitude->{$coordinates} <= 3 and $rand < 0.6) {
	  $thing = "grass";
      }
      my $colour = "light-green";
      $colour = "light-grey" if $altitude->{$coordinates} >= 6;
      $world->{$coordinates} = "$colour $thing";
    }
  }
}

sub settlements {
  my $self = shift;
  my ($world, $flow) = @_;
  my @settlements;
  my $max = $height * $width;
  # do not match forest-hill
  my @candidates = shuffle sort grep { $world->{$_} =~ /\b(fir-forest|forest(?!-hill))\b/ } keys %$world;
  @candidates = $self->remove_closer_than(2, @candidates);
  @candidates = @candidates[0 .. int($max/10 - 1)] if @candidates > $max/10;
  push(@settlements, @candidates);
  for my $coordinates (@candidates) {
    $world->{$coordinates} =~ s/fir-forest/firs thorp/
	or $world->{$coordinates} =~ s/forest(?!-hill)/trees thorp/;
  }
  @candidates = shuffle sort grep { $world->{$_} =~ /(?<!fir-)forest(?!-hill)/ and $flow->{$_}} keys %$world;
  @candidates = $self->remove_closer_than(5, @candidates);
  @candidates = @candidates[0 .. int($max/20 - 1)] if @candidates > $max/20;
  push(@settlements, @candidates);
  for my $coordinates (@candidates) {
    $world->{$coordinates} =~ s/forest/trees village/;
  }
  @candidates = shuffle sort grep { $world->{$_} =~ /(?<!fir-)forest(?!-hill)/ and $flow->{$_} } keys %$world;
  @candidates = $self->remove_closer_than(10, @candidates);
  @candidates = @candidates[0 .. int($max/40 - 1)] if @candidates > $max/40;
  push(@settlements, @candidates);
  for my $coordinates (@candidates) {
    $world->{$coordinates} =~ s/forest/trees town/;
  }
  @candidates = shuffle sort grep { $world->{$_} =~ /white mountain\b/ } keys %$world;
  @candidates = $self->remove_closer_than(10, @candidates);
  @candidates = @candidates[0 .. int($max/40 - 1)] if @candidates > $max/40;
  push(@settlements, @candidates);
  for my $coordinates (@candidates) {
    $world->{$coordinates} =~ s/white mountain\b/white mountain law/;
  }
  @candidates = shuffle sort grep { $world->{$_} =~ /swamp/ } keys %$world;
  @candidates = $self->remove_closer_than(10, @candidates);
  @candidates = @candidates[0 .. int($max/40 - 1)] if @candidates > $max/40;
  push(@settlements, @candidates);
  for my $coordinates (@candidates) {
    $world->{$coordinates} =~ s/swamp/swamp2 chaos/;
  }
  return @settlements;
}

sub trails {
  my $self = shift;
  my ($altitude, $settlements) = @_;
  # look for a neighbor that is as low as possible and nearby
  my %trails;
  my @from = shuffle @$settlements;
  my @to = shuffle @$settlements;
  for my $from (@from) {
    my ($best, $best_distance, $best_altitude);
    for my $to (@to) {
      next if $from eq $to;
      my $distance = $self->distance($from, $to);
      $log->debug("Considering $from-$to: distance $distance, altitude " . $altitude->{$to});
      if ($distance <= 3
	  and (not $best_distance or $distance <= $best_distance)
	  and (not $best or $altitude->{$to} < $best_altitude)) {
	$best = $to;
	$best_altitude = $altitude->{$best};
	$best_distance = $distance;
      }
    }
    next if not $best;
    # skip if it already exists in the other direction
    next if $trails{"$best-$from"};
    $trails{"$from-$best"} = 1;
    $log->debug("Trail $from-$best");
  }
  return keys %trails;
}

sub cliffs {
  my $self = shift;
  my ($world, $altitude) = @_;
  my @neighbors = $self->neighbors();
  # hexes with altitude difference bigger than 1 have cliffs
  for my $coordinates (keys %$world) {
    for my $i (@neighbors) {
      my ($x, $y) = $self->neighbor($coordinates, $i);
      next unless $self->legal($x, $y);
      my $other = coordinates($x, $y);
      if ($altitude->{$coordinates} - $altitude->{$other} >= 2) {
	if (@neighbors == 6) {
	  $world->{$coordinates} .= " cliff$i";
	} else { # square
	  $world->{$coordinates} .= " cliffs$i";
	}
      }
    }
  }
}

sub generate {
  my $self = shift;
  my ($world, $altitude, $water, $rivers, $settlements, $trails, $canyons, $step) = @_;
  # %flow indicates that there is actually a river in this hex
  my $flow = {};

  my @code = (
    sub { $self->flat($altitude);
	  $self->altitude($world, $altitude); },
    sub { $self->bumps($world, $altitude); },
    sub { $self->mountains($world, $altitude); },
    sub { $self->water($world, $altitude, $water); },
    sub { $self->lakes($world, $altitude, $water); },
    sub { $self->flood($world, $altitude, $water); },
    sub { $self->bogs($world, $altitude, $water, $flow); },
    sub { push(@$rivers, $self->rivers($world, $altitude, $water, $flow, 8));
	  push(@$rivers, $self->rivers($world, $altitude, $water, $flow, 7)); },
    sub { push(@$canyons, $self->canyons($world, $altitude, $rivers)); },
    sub { $self->swamps($world, $altitude, $water, $flow); },
    sub { $self->forests($world, $altitude, $flow); },
    sub { $self->bushes($world, $altitude, $water, $flow); },
    sub { $self->cliffs($world, $altitude); },
    sub { push(@$settlements, $self->settlements($world, $flow)); },
    sub { push(@$trails, $self->trails($altitude, $settlements)); },
    # make sure you look at "alpine_document.html.ep" if you change this list!
    # make sure you look at '/alpine/document' if you add to this list
      );

  # $step 0 runs all the code; note that we can't simply cache those results
  # because we need to start over with the same seed!
  my $i = 1;
  while (@code) {
    shift(@code)->();
    return if $step == $i++;
  }
}

sub generate_map {
  my $self = shift;
  # The parameters turn into class variables.
  $width = shift // 30;
  $height = shift // 10;
  $steepness = shift // 3;
  $peaks = shift // int($width * $height / 40);
  $peak = shift // 10;
  $bumps = shift // int($width * $height / 40);
  $bump = shift // 2;
  $bottom = shift // 0;
  $arid = shift // 2;
  my $seed = shift||time;
  my $url = shift;
  my $step = shift||0;

  # For documentation purposes, I want to be able to set the pseudo-random
  # number seed using srand and rely on rand to reproduce the same sequence of
  # pseudo-random numbers for the same seed. The key point to remember is that
  # the keys function will return keys in random order. So if we look over the
  # result of keys, we need to look at the code in the loop: If order is
  # important, that wont do. We need to sort the keys. If we want the keys to be
  # pseudo-shuffled, use shuffle sort keys.
  srand($seed);

  # keys for all hashes are coordinates such as "0101".
  # %world is the description with values such as "green forest".
  # %altitude is the altitude with values such as 3.
  # %water is the preferred direction water would take with values such as 0
  # (north west); 0 means we need to use "if defined".
  # @rivers are the rivers with values such as ["0102", "0202"]
  # @settlements are are the locations of settlements such as "0101"
  # @trails are the trails connecting these with values as "0102-0202"
  # $step is how far we want map generation to go where 0 means all the way
  my ($world, $altitude, $water, $rivers, $settlements, $trails, $canyons) =
      ({}, {}, {}, [], [], [], []);
  $self->generate($world, $altitude, $water, $rivers, $settlements, $trails, $canyons, $step);

  # when documenting or debugging, do this before collecting lines
  if ($step > 0) {
    # add a height label at the very end
    if ($step) {
      for my $coordinates (keys %$world) {
	$world->{$coordinates} .= ' "' . $altitude->{$coordinates} . '"';
      }
    }
  }
  if ($step < 1 or $step > 8) {
    # remove arrows – these should not be rendered but they are because #arrow0
    # is present in other SVG files in the same document
    for my $coordinates (keys %$world) {
      $world->{$coordinates} =~ s/ arrow\d//;
    }
  }

  local $" = "-"; # list items separated by -
  my @lines;
  push(@lines, map { $_ . " " . $world->{$_} } sort keys %$world);
  push(@lines, map { "@$_ canyon" } @$canyons);
  push(@lines, map { "@$_ river" } @$rivers);
  push(@lines, map { "$_ trail" } @$trails);
  push(@lines, "include $contrib/gnomeyland.txt");

  # when documenting or debugging, add some more lines at the end
  if ($step > 0) {
    # visualize height
    push(@lines,
	 map {
	   my $n = int(25.5 * $_);
	   qq{height$_ attributes fill="rgb($n,$n,$n)"};
	 } (0 .. 10));
    # visualize water flow
    push(@lines, $self->arrows());
  }

  push(@lines, "# Seed: $seed");
  push(@lines, "# Documentation: " . $url) if $url;
  my $map = join("\n", @lines);
  return $map;
}

package Schroeder::Hex;

use parent -norequire, 'Schroeder';

sub neighbors { 0 .. 5 }

sub neighbors2 { 0 .. 11 }

sub random_neighbor { int(rand(6)) }

sub random_neighbor2 { int(rand(12)) }

my $delta_hex = [
  # x is even
  [[-1,  0], [ 0, -1], [+1,  0], [+1, +1], [ 0, +1], [-1, +1]],
  # x is odd
  [[-1, -1], [ 0, -1], [+1, -1], [+1,  0], [ 0, +1], [-1,  0]]];

sub neighbor {
  my $self = shift;
  # $hex is [x,y] or "0x0y" and $i is a number 0 .. 5
  my ($hex, $i) = @_;
  die join(":", caller) . ": undefined direction for $hex\n" unless defined $i;
  $hex = [$self->xy($hex)] unless ref $hex;
  return ($hex->[0] + $delta_hex->[$hex->[0] % 2]->[$i]->[0],
	  $hex->[1] + $delta_hex->[$hex->[0] % 2]->[$i]->[1]);
}

my $delta_hex2 = [
  # x is even
  [[-2, +1], [-2,  0], [-2, -1], [-1, -1], [ 0, -2], [+1, -1],
   [+2, -1], [+2,  0], [+2, +1], [+1, +2], [ 0, +2], [-1, +2]],
  # x is odd
  [[-2, +1], [-2,  0], [-2, -1], [-1, -2], [ 0, -2], [+1, -2],
   [+2, -1], [+2,  0], [+2, +1], [+1, +1], [ 0, +2], [-1, +1]]];

sub neighbor2 {
  my $self = shift;
  # $hex is [x,y] or "0x0y" and $i is a number 0 .. 11
  my ($hex, $i) = @_;
  die join(":", caller) . ": undefined direction for $hex\n" unless defined $i;
  $hex = [$self->xy($hex)] unless ref $hex;
  return ($hex->[0] + $delta_hex2->[$hex->[0] % 2]->[$i]->[0],
	  $hex->[1] + $delta_hex2->[$hex->[0] % 2]->[$i]->[1]);
}

sub distance {
  my $self = shift;
  my ($x1, $y1, $x2, $y2) = @_;
  if (@_ == 2) {
    ($x1, $y1, $x2, $y2) = map { $self->xy($_) } @_;
  }
  # transform the coordinate system into a decent system with one axis tilted by
  # 60°
  $y1 = $y1 - POSIX::ceil($x1/2);
  $y2 = $y2 - POSIX::ceil($x2/2);
  if ($x1 > $x2) {
    # only consider moves from left to right and transpose start and
    # end point to make it so
    my ($t1, $t2) = ($x1, $y1);
    ($x1, $y1) = ($x2, $y2);
    ($x2, $y2) = ($t1, $t2);
  }
  if ($y2>=$y1) {
    # if it the move has a downwards component add Δx and Δy
    return $x2-$x1 + $y2-$y1;
  } else {
    # else just take the larger of Δx and Δy
    return $x2-$x1 > $y1-$y2 ? $x2-$x1 : $y1-$y2;
  }
}

sub arrows {
  my $self = shift;
  return
      qq{<marker id="arrow" markerWidth="6" markerHeight="6" refX="6" refY="3" orient="auto"><path d="M6,0 V6 L0,3 Z" style="fill: black;" /></marker>},
      map {
	my $angle = 60 * $_;
	qq{<path id="arrow$_" transform="rotate($angle)" d="M-11.5,-5.8 L11.5,5.8" style="stroke: black; stroke-width: 3px; fill: none; marker-start: url(#arrow);"/>},
  } ($self->neighbors());
}

package Schroeder::Square;

use parent -norequire, 'Schroeder';

sub neighbors { 0 .. 3 }

sub neighbors2 { 0 .. 7 }

sub random_neighbor { int(rand(4)) }

sub random_neighbor2 { int(rand(8)) }

my $delta_square = [[-1,  0], [ 0, -1], [+1,  0], [ 0, +1]];

sub neighbor {
  my $self = shift;
  # $hex is [x,y] or "0x0y" and $i is a number 0 .. 3
  my ($hex, $i) = @_;
  die join(":", caller) . ": undefined direction for $hex\n" unless defined $i;
  $hex = [$self->xy($hex)] unless ref $hex;
  return ($hex->[0] + $delta_square->[$i]->[0],
	  $hex->[1] + $delta_square->[$i]->[1]);
}

my $delta_square2 = [
  [-2,  0], [-1, -1], [ 0, -2], [+1, -1],
  [+2,  0], [+1, +1], [ 0, +2], [-1, +1]];

sub neighbor2 {
  my $self = shift;
  # $hex is [x,y] or "0x0y" and $i is a number 0 .. 7
  my ($hex, $i) = @_;
  die join(":", caller) . ": undefined direction for $hex\n" unless defined $i;
  die join(":", caller) . ": direction $i not supported for square $hex\n" if $i > 7;
  $hex = [$self->xy($hex)] unless ref $hex;
  return ($hex->[0] + $delta_square2->[$i]->[0],
	  $hex->[1] + $delta_square2->[$i]->[1]);
}

sub distance {
  my $self = shift;
  my ($x1, $y1, $x2, $y2) = @_;
  if (@_ == 2) {
    ($x1, $y1, $x2, $y2) = map { $self->xy($_) } @_;
  }
  return abs($x2 - $x1) + abs($y2 - $y1);
}

sub arrows {
  my $self = shift;
  return
      qq{<marker id="arrow" markerWidth="6" markerHeight="6" refX="6" refY="3" orient="auto"><path d="M6,0 V6 L0,3 Z" style="fill: black;" /></marker>},
      map {
	my $angle = 90 * $_;
	qq{<path id="arrow$_" transform="rotate($angle)" d="M-15,0 H30" style="stroke: black; stroke-width: 3px; fill: none; marker-start: url(#arrow);"/>},
  } ($self->neighbors());
}

package Gridmapper;
use List::Util qw'shuffle none any';
use List::MoreUtils qw'pairwise';
use Class::Struct;

# Currently empty
struct Gridmapper => {};

# This is the meta grid for the geomorphs.
my @dungeon_dimensions = (3, 3);
# This is the grid for a particular geomorph.
my @room_dimensions = (5, 5);
# Add two tiles for the edges.
my $row = $dungeon_dimensions[0] * $room_dimensions[0] + 4;
my $col = $dungeon_dimensions[1] * $room_dimensions[1] + 4;
my $max = $row * $col - 1;
# (0,0) starts at the top left and goes rows before columns, like text.

sub generate_map {
  my $self = shift;
  my $pillars = shift;
  my $rooms = [map { generate_room($_, $pillars) } (1 .. 5)];
  my $shape = shape(scalar(@$rooms));
  my $tiles = add_rooms($rooms, $shape);
  $tiles = add_corridors($tiles, $shape);
  $tiles = add_doors($tiles);
  $tiles = add_stair($tiles);
  $tiles = fix_corners($tiles);
  $tiles = fix_pillars($tiles) if $pillars;
  my $text = to_text($tiles);
}

sub generate_room {
  my $num = shift;
  my $pillars = shift;
  my $r = rand();
  if ($r < 0.9) {
    return generate_random_room($num);
  } elsif ($r < 0.95 and $pillars) {
    return generate_pillar_room($num);
  } else {
    return generate_fancy_corner_room($num);
  }
}

sub generate_random_room {
  my $num = shift;
  # generate the tiles necessary for a single geomorph
  my @tiles;
  my @dimensions = (2 + int(rand(3)), 2 + int(rand(3)));
  my @start = pairwise { int(rand($b - $a)) } @dimensions, @room_dimensions;
  # $log->debug("New room starting at (@start) for dimensions (@dimensions)");
  for my $x ($start[0] .. $start[0] + $dimensions[0] - 1) {
    for my $y ($start[1] .. $start[1] + $dimensions[1] - 1) {
      $tiles[$x + $y * $room_dimensions[0]] = ["empty"];
    }
  }
  my $x = $start[0] + int($dimensions[0]/2);
  my $y = $start[1] + int($dimensions[1]/2);
  push(@{$tiles[$x + $y * $room_dimensions[0]]}, "\"$num\"");
  return \@tiles;
}

sub generate_fancy_corner_room {
  my $num = shift;
  my @tiles;
  my @dimensions = (3 + int(rand(2)), 3 + int(rand(2)));
  my @start = pairwise { int(rand($b - $a)) } @dimensions, @room_dimensions;
  # $log->debug("New room starting at (@start) for dimensions (@dimensions)");
  for my $x ($start[0] .. $start[0] + $dimensions[0] - 1) {
    for my $y ($start[1] .. $start[1] + $dimensions[1] - 1) {
      push(@{$tiles[$x + $y * $room_dimensions[0]]}, "empty");
      # $log->debug("$x $y @{$tiles[$x + $y * $room_dimensions[0]]}");
    }
  }
  my $type = rand() < 0.5 ? "arc" : "diagonal";
  $tiles[$start[0] + $start[1] * $room_dimensions[0]] = ["$type-se"];
  $tiles[$start[0] + $dimensions[0] + $start[1] * $room_dimensions[0] -1] = ["$type-sw"];
  $tiles[$start[0] + ($start[1] + $dimensions[1] - 1) * $room_dimensions[0]] = ["$type-ne"];
  $tiles[$start[0] + $dimensions[0] + ($start[1] + $dimensions[1] - 1) * $room_dimensions[0] - 1] = ["$type-nw"];
  my $x = $start[0] + int($dimensions[0]/2);
  my $y = $start[1] + int($dimensions[1]/2);
  push(@{$tiles[$x + $y * $room_dimensions[0]]}, "\"$num\"");
  return \@tiles;
}

sub generate_pillar_room {
  my $num = shift;
  my @tiles;
  my @dimensions = (3 + int(rand(2)), 3 + int(rand(2)));
  my @start = pairwise { int(rand($b - $a)) } @dimensions, @room_dimensions;
  # $log->debug("New room starting at (@start) for dimensions (@dimensions)");
  my $type = "|";
  for my $x ($start[0] .. $start[0] + $dimensions[0] - 1) {
    for my $y ($start[1] .. $start[1] + $dimensions[1] - 1) {
      if ($type eq "|" and ($x == $start[0] or $x == $start[0] + $dimensions[0] - 1)
	  or $type eq "-" and ($y == $start[1] or $y == $start[1] + $dimensions[1] - 1)) {
	push(@{$tiles[$x + $y * $room_dimensions[0]]}, "pillar");
      } else {
	push(@{$tiles[$x + $y * $room_dimensions[0]]}, "empty");
	# $log->debug("$x $y @{$tiles[$x + $y * $room_dimensions[0]]}");
      }
    }
  }
  my $x = $start[0] + int($dimensions[0]/2);
  my $y = $start[1] + int($dimensions[1]/2);
  push(@{$tiles[$x + $y * $room_dimensions[0]]}, "\"$num\"");
  return \@tiles;
}

sub one {
  return $_[int(rand(scalar @_))];
}

sub shape {
  # return an array of deltas to shift rooms around
  my $num = shift;
  my $shape = [];
  if ($num == 5) {
    $shape= one(
      # The Nine Forms of the Five Room Dungeon
      # https://gnomestew.com/the-nine-forms-of-the-five-room-dungeon/
      #
      # The Railroad
      #
      #       5        5     4--5         5--4
      #       |        |     |		     |
      #       4     3--4     3       5--4    3
      #       |     |        |          |    |
      # 1--2--3  1--2     1--2    1--2--3 1--2
      [[0, 2], [1, 2], [2, 2], [2, 1], [2, 0]],
      [[0, 2], [1, 2], [1, 1], [2, 1], [2, 0]],
      [[0, 2], [1, 2], [1, 1], [1, 0], [2, 0]],
      [[0, 2], [1, 2], [2, 2], [2, 1], [1, 1]],
      [[0, 2], [1, 2], [1, 1], [1, 0], [0, 0]],
      #
      # Note how whenever there is a non-linear connection, there is a an extra
      # element pointing to the "parent". This is necessary for all but the
      # railroads.
      #
      # Foglio's Snail
      #
      #    5  4
      #    |  |
      # 1--2--3
      [[0, 2], [1, 2], [2, 2], [2, 1], [1, 1, 1]],
      #
      # The Fauchard Fork
      #
      #    5       5
      #    |       |
      #    3--4 4--3 5--3--4
      #    |       |    |
      # 1--2    1--2 1--2
      [[0, 2], [1, 2], [1, 1], [2, 1], [1, 0, 2]],
      [[0, 2], [1, 2], [1, 1], [0, 1], [1, 0, 2]],
      [[0, 2], [1, 2], [1, 1], [2, 1], [0, 1, 2]],
      #
      # The Moose
      #
      #            4
      #	           |
      # 5     4 5  3
      # |     | |  |
      # 1--2--3 1--2
      [[0, 2], [1, 2], [2, 2], [2, 1], [0, 1, 0]],
      [[0, 2], [1, 2], [1, 1], [1, 0], [0, 1, 0]],
      #
      # The Paw
      #
      #    5
      #    |
      # 3--2--4
      #    |
      #    1
      [[1, 2], [1, 1], [0, 1], [2, 1, 1], [1, 0, 1]],
      #
      # The Arrow
      #
      #    3
      #	   |
      #    2
      #    |
      # 5--1--4
      [[1, 2], [1, 1], [1, 0], [2, 2, 0], [0, 2, 0]],
      #
      # The Cross
      #
      #    5
      #    |
      # 3--1--4
      #    |
      #    2
      [[1, 1], [1, 2], [0, 1, 0], [2, 1, 0], [1, 0, 0]],
      #
      # The Nose Ring
      #
      #    5--4  2--3--4
      #    |  |  |  |
      # 1--2--3  1--5
      # [[0, 2], [1, 2], [2, 2], [2, 1], [1, 1, 1, 3]],
      [[0, 2], [0, 1], [1, 1], [2, 1], [1, 2, 0, 2]],
	);
  }
  # $log->debug(join(", ", map { "[@$_]"} @$shape));
  my $r = rand;
  if ($r < 0.20) {
    # flip vertically
    $shape = [map{ $_->[1] = $dungeon_dimensions[1] - 1 - $_->[1]; $_ } @$shape];
    # $log->debug("flip vertically: " . join(", ", map { "[@$_]"} @$shape));
  } elsif ($r < 0.4) {
    # flip horizontally
    $shape = [map{ $_->[0] = $dungeon_dimensions[0] - 1 - $_->[0]; $_ } @$shape];
    # $log->debug("flip horizontally: " . join(", ", map { "[@$_]"} @$shape));
  } elsif ($r < 0.6) {
    # flip diagonally
    $shape = [map{ my $t = $_->[1]; $_->[1] = $_->[0]; $_->[0] = $t; $_ } @$shape];
    # $log->debug("flip diagonally: " . join(", ", map { "[@$_]"} @$shape));
  } elsif ($r < 0.8) {
    # flip diagonally
    $shape = [map{ $_->[0] = $dungeon_dimensions[0] - 1 - $_->[0];
		   $_->[1] = $dungeon_dimensions[1] - 1 - $_->[1];
		   $_ } @$shape];
    # $log->debug("flip both: " . join(", ", map { "[@$_]"} @$shape));
  }
  $log->error("No appropriate dungeon shape found") unless $shape;
  return $shape;
}

sub add_rooms {
  # Get the rooms and the deltas, draw it all on a big grid. Don't forget the
  # two-tile border around it all.
  my $rooms = shift;
  my $deltas = shift;
  my @tiles;
  pairwise {
    my $room = $a;
    my $delta = $b;
    # $log->debug("Draw room shifted by delta (@$delta)");
    # copy the room, shifted appropriately
    for my $x (0 .. $room_dimensions[0] - 1) {
      for my $y (0 .. $room_dimensions[0] - 1) {
	my $v = $tiles[$x + $delta->[0] * $room_dimensions[0] + 2
		       + ($y + $delta->[1] * $room_dimensions[1] + 2)
		       * $row]
	    = $room->[$x + $y * $room_dimensions[0]];
	# $log->debug(sprintf("%02d%02d (%d) %s", $x + $delta->[0] * $room_dimensions[0],
	# 		    $y + $delta->[1] * $room_dimensions[1],
	# 		    $x + $delta->[0] * $room_dimensions[0]
	# 		    + ($y + $delta->[1] * $room_dimensions[1]) * $row,
	# 		    join(" ", @$v))) if $v;
      }
    }
  } @$rooms, @$deltas;
  return \@tiles;
}

sub add_corridors {
  my $tiles = shift;
  my $shapes = shift;    # reference to the original
  my @shapes = @$shapes; # a copy that gets shorter
  my $from = shift(@shapes);
  my $delta;
  for my $to (@shapes) {
    if (@$to == 2) {
      # The default case is that the preceding shape is our parent. A simple
      # railroad!
      # $log->debug("from @$from to @$to");
      $tiles = add_corridor($tiles, $from, $to, get_delta($from, $to));
      $from = $to;
    } else {
      # In case the shapes are not connected in order, the parent shapes are
      # available as extra elements.
      for my $from (map { $shapes->[$_] } @$to[2 .. $#$to]) {
	# $log->debug(" from @$from to @$to");
	$tiles = add_corridor($tiles, $from, $to, get_delta($from, $to));
      }
    }
  }
  return $tiles;
}

sub get_delta {
  my $from = shift;
  my $to = shift;
  # Direction: north is minus an entire row, south is plus an entire row, east
  # is plus one, west is minus one. Return an array reference with three
  # elements: how to get the next element and how to get the two elements to the
  # left and right.
  if ($to->[0] < $from->[0]) {
    # $log->debug("west");
    return [-1, - $row, $row];
  } elsif ($to->[0] > $from->[0]) {
    # $log->debug("east");
    return [1, - $row, $row];
  } elsif ($to->[1] < $from->[1]) {
    # $log->debug("north");
    return [- $row, 1, -1];
  } elsif ($to->[1] > $from->[1]) {
    # $log->debug("south");
    return [$row, 1, -1];
  } else {
    $log->warn("unclear direction: bogus shape?");
  }
}

sub position_in {
  # Return a position in the big array corresponding to the midpoint in a room.
  # Don't forget the two-tile border.
  my $delta = shift;
  my $x = int($room_dimensions[0]/2) + 2;
  my $y = int($room_dimensions[1]/2) + 2;
  return $x + $delta->[0] * $room_dimensions[0]
      + ($y + $delta->[1] * $room_dimensions[1]) * $row;
}

sub add_corridor {
  # In the example below, we're going east from F to T. In order to make sure
  # that we also connect rooms in (0,0)-(1,1), we start one step earlier (1,2)
  # and end one step later (8,2).
  #
  #  0123456789
  # 0
  # 1
  # 2  F    T
  # 3
  # 4
  my $tiles = shift;
  my $from = shift;
  my $to = shift;
  # Delta has three elements: forward, left and right indexes.
  my $delta = shift;
  # Convert $from and $to to indexes into the tiles array.
  $from = position_in($from) - 2 * $delta->[0];
  $to = position_in($to) + 2 * $delta->[0];
  my $n = 0;
  my $contact = 0;
  my $started = 0;
  my @undo;
  # $log->debug("Checking $from-$to");
  while (not grep { $to == ($from + $_) } @$delta) {
    $from += $delta->[0];
    # contact is if we're on a room, or to the left or right of a room (but not in front of a room)
    $contact = any { something($tiles, $from, $_) } 0, $delta->[1], $delta->[2];
    if ($contact) {
      $started = 1;
      @undo = ();
    } else {
      push(@undo, $from);
    }
    $tiles->[$from] = ["empty"] if $started and not $tiles->[$from];
    last if $n++ > 20; # safety!
  }
  for (@undo) {
    $tiles->[$_] = undef;
  }
  return $tiles;
}

sub add_doors {
  my $tiles = shift;
  # Doors can be any tile that has three or four neighbours, including
  # diagonally:
  #
  # ▓▓   ▓▓
  # ▓▓▒▓ ▓▓▒▓
  #      ▓▓
  my @types = qw(door door door door door door secret secret archway concealed);
  # first two neighbours must be clear, the next two must be set, and one of the others must be set as well
  my %test = (n => [-1, 1, -$row, $row, -$row + 1, -$row - 1],
	      e => [-$row, $row, -1, 1, $row + 1, -$row + 1],
	      s => [-1, 1, -$row, $row, $row + 1, $row - 1],
	      w => [-$row, $row, -1, 1, $row - 1, -$row - 1]);
  my @doors;
  for my $here (shuffle 1 .. scalar(@$tiles) - 1) {
    for my $dir (shuffle qw(n e s w)) {
      if ($tiles->[$here]
	  and not something($tiles, $here, $test{$dir}->[0])
	  and not something($tiles, $here, $test{$dir}->[1])
	  and something($tiles, $here, $test{$dir}->[2])
	  and something($tiles, $here, $test{$dir}->[3])
	  and (something($tiles, $here, $test{$dir}->[4])
	       or something($tiles, $here, $test{$dir}->[5]))
	  and not doors_nearby($here, \@doors)) {
	$log->warn("$here content isn't 'empty'") unless $tiles->[$here]->[0] eq "empty";
	my $type = one(@types);
	my $variant = $dir;
	my $target = $here;
	# this makes sure doors are on top
	if ($dir eq "s") { $target += $row; $variant = "n"; }
	elsif ($dir eq "e") { $target += 1; $variant = "w"; }
	push(@{$tiles->[$target]}, "$type-$variant");
	push(@doors, $here);
      }
    }
  }
  return $tiles;
}

sub doors_nearby {
  my $here = shift;
  my $doors = shift;
  for my $door (@$doors) {
    return 1 if distance($door, $here) < 2;
  }
  return 0;
}

sub distance {
  my $from = shift;
  my $to = shift;
  my $dx = $to % $row - $from % $row;
  my $dy = int($to/$row) - int($from/$row);
  return sqrt($dx * $dx + $dy * $dy);
}

sub add_stair {
  my $tiles = shift;
  # find the middle using the label
  my $start;
  for my $one (0 .. scalar(@$tiles) - 1) {
    next unless $tiles->[$one];
    $start = $one;
    last if grep { $_ eq '"1"' } @{$tiles->[$one]};
  }
  # The first test refers to a tile that must be set to "empty" (where the stair
  # will end), all others must be undefined. Note that stairs are anchored at
  # the top end, and we're placing a stair that goes *down*. So what we're
  # looking for is the point (4,1) in the image below:
  #
  #   12345
  # 1 EE<<
  # 2 EE
  #
  # Remember, +1 is east, -1 is west, -$row is north, +$row is south. The anchor
  # point we're testing is already known to be undefined.
  my %test = (n => [-2 * $row,
		    -$row - 1, -$row, -$row + 1,
		    -1, +1,
		    +$row - 1, +$row, +$row + 1],
	      e => [+2,
		    -$row + 1, +1, +$row + 1,
		    -$row, +$row,
		    -$row - 1, -1, +$row - 1]);
  $test{s} = [map { -$_ } @{$test{n}}];
  $test{w} = [map { -$_ } @{$test{e}}];
  # First round: limit ourselves to stair positions close to the start.
  my %candidates;
  for my $here (shuffle 0 .. scalar(@$tiles) - 1) {
    next if $tiles->[$here];
    my $distance = distance($here, $start);
    $candidates{$here} = $distance if $distance <= 4;
  }
  # Second round: for each candidate, test stair placement and record the
  # distance of the landing to the start and the direction of every successful
  # stair.
  my $stair;
  my $stair_dir;
  my $stair_distance = $max;
  for my $here (sort {$a cmp $b} keys %candidates) {
    # push(@{$tiles->[$here]}, "red");
    for my $dir (shuffle qw(n e w s)) {
      my @test = @{$test{$dir}};
      my $first = shift(@test);
      if (# the first test is an empty tile: this the stair's landing
	  empty($tiles, $here, $first)
	  # and the stair is surrounded by empty space
	  and none { something($tiles, $here, $_) } @test) {
	my $distance = distance($here + $first, $start);
	if ($distance < $stair_distance) {
	  # $log->debug("Considering stair-$dir for $here ($distance)");
	  $stair = $here;
	  $stair_dir = $dir;
	  $stair_distance = $distance;
	}
      }
    }
  }
  if (defined $stair) {
    push(@{$tiles->[$stair]}, "stair-$stair_dir");
    return $tiles;
  }
  # $log->debug("Unable to place a regular stair, trying to place a spiral staircase");
  for my $here (shuffle 0 .. scalar(@$tiles) - 1) {
    next unless $tiles->[$here];
    if (# close by
	distance($here, $start) < 3
	# and the landing is empty (no statue, doors n or w)
	and @{$tiles->[$here]} == 1
	and $tiles->[$here]->[0] eq "empty"
	# and the landing to the south has no door n
	and not grep { /-n$/ } @{$tiles->[$here+$row]}
	# and the landing to the east has no door w
	and not grep { /-w$/ } @{$tiles->[$here+1]}) {
      $log->debug("Placed spiral stair at $here");
      $tiles->[$here]->[0] = "stair-spiral";
      return $tiles;
    }
  }
  $log->warn("Unable to place a stair!");
  return $tiles;
}

sub fix_corners {
  my $tiles = shift;
  my %look = (n => -$row, e => 1, s => $row, w => -1);
  for my $here (0 .. scalar(@$tiles) - 1) {
    for (@{$tiles->[$here]}) {
      if (/^(arc|diagonal)-(ne|nw|se|sw)$/) {
	my $dir = $2;
	# debug_neighbours($tiles, $here);
	if (substr($dir, 0, 1) eq "n" and $here + $row < $max and $tiles->[$here + $row] and @{$tiles->[$here + $row]}
	    or substr($dir, 0, 1) eq "s" and $here > $row and $tiles->[$here - $row] and @{$tiles->[$here - $row]}
	    or substr($dir, 1) eq "e" and $here > 0 and $tiles->[$here - 1] and @{$tiles->[$here - 1]}
	    or substr($dir, 1) eq "w" and $here < $max and $tiles->[$here + 1] and @{$tiles->[$here + 1]}) {
	  $_ = "empty";
	}
      }
    }
  }
  return $tiles;
}

sub fix_pillars {
  my $tiles = shift;
  my %test = (n => [-$row, -$row - 1, -$row + 1],
	      e => [1, 1 - $row, 1 + $row],
	      s => [$row, $row - 1, $row + 1],
	      w => [-1, -1 - $row, -1 + $row]);
  for my $here (0 .. scalar(@$tiles) - 1) {
  TILE:
    for (@{$tiles->[$here]}) {
      if ($_ eq "pillar") {
	# $log->debug("$here: $_");
	# debug_neighbours($tiles, $here);
	for my $dir (qw(n e w s)) {
	  if (something($tiles, $here, $test{$dir}->[0])
	      and not something($tiles, $here, $test{$dir}->[1])
	      and not something($tiles, $here, $test{$dir}->[2])) {
	    # $log->debug("Removing pillar $here");
	    $_ = "empty";
	    next TILE;
	  }
	}
      }
    }
  }
  return $tiles;
}

sub legal {
  # is this position on the map?
  my $here = shift;
  my $delta = shift;
  return if $here + $delta < 0 or $here + $delta > $max;
  return if $here % $row == 0 and $delta == -1;
  return if $here % $row == $row and $delta == 1;
  return 1;
}

sub something {
  # Is there something at this legal position? Off the map means there is
  # nothing at the position.
  my $tiles = shift;
  my $here = shift;
  my $delta = shift;
  return if not legal($here, $delta);
  return @{$tiles->[$here + $delta]} if $tiles->[$here + $delta];
}

sub empty {
  # Is this position legal and empty? We're looking for the "empty" tile!
  my $tiles = shift;
  my $here = shift;
  my $delta = shift;
  return if not legal($here, $delta);
  return grep { $_ eq "empty" } @{$tiles->[$here + $delta]};
}

sub debug_neighbours {
  my $tiles = shift;
  my $here = shift;
  my @n;
  if ($here > $row and $tiles->[$here - $row] and @{$tiles->[$here - $row]}) {
    push(@n, "n: @{$tiles->[$here - $row]}");
  }
  if ($here + $row <= $max and $tiles->[$here + $row] and @{$tiles->[$here + $row]}) {
    push(@n, "s: @{$tiles->[$here + $row]}");
  }
  if ($here > 0 and $tiles->[$here - 1] and @{$tiles->[$here - 1]}) {
    push(@n, "w: @{$tiles->[$here - 1]}");
  }
  if ($here < $max and $tiles->[$here + 1] and @{$tiles->[$here + 1]}) {
    push(@n, "e: @{$tiles->[$here + 1]}");
  }
  $log->debug("Neighbours of $here: @n");
  for (-$row-1, -$row, -$row+1, -1, +1, $row-1, $row, $row+1) {
    eval { $log->debug("Neighbours of $here+$_: @{$tiles->[$here + $_]}") };
  }
}

sub to_text {
  # Don't forget the border of two tiles.
  my $tiles = shift;
  my $text = "include $contrib/gridmapper.txt\n";
  for my $x (0 .. $row - 1) {
    for my $y (0 .. $col - 1) {
      my $tile = $tiles->[$x + $y * $row];
      if ($tile) {
	$text .= sprintf("%02d%02d @$tile\n", $x + 1, $y + 1);
      }
    }
  }
  return $text;
}

package Mojolicious::Command::render;
use Mojo::Base 'Mojolicious::Command';

has description => 'Render map from STDIN';

has usage => <<EOF;
Usage example:
perl text-mapper.pl render < contrib/forgotten-depths.txt > forgotten-depths.svg

This reads a map description from STDIN and prints the resulting SVG map to
STDOUT.
EOF

sub run {
  my ($self, @args) = @_;
  local $/ = undef;
  my $map = new Mapper::Hex;
  $map->initialize(<STDIN>);
  print $map->svg;
}

package Mojolicious::Command::random;
use Mojo::Base 'Mojolicious::Command';

has description => 'Print a random map to STDOUT';

has usage => <<EOF;
Usage example:
perl text-mapper.pl random > map.txt

This prints a random map description to STDOUT.

You can also pipe this:

perl text-mapper.pl random | perl text-mapper.pl render > map.svg

EOF

sub run {
  my ($self, @args) = @_;
  print Smale::generate_map();
}

package main;

use Mojolicious::Lite;
use Mojo::DOM;
use Mojo::Util qw(xml_escape);
use Pod::Simple::HTML;
use Pod::Simple::Text;

plugin Config => {default => {
  loglevel => 'warn',
  contrib => 'https://campaignwiki.org/contrib', }};

$log = Mojo::Log->new;
$log->level(app->config('loglevel'));
$debug = $log->level eq 'debug';
$contrib = app->config('contrib');

get '/' => sub {
  my $c = shift;
  my $param = $c->param('map');
  if ($param) {
    my $map;
    if ($c->param('type') and $c->param('type') eq 'square') {
      $map = new Mapper::Square;
    } else {
      $map = new Mapper::Hex;
    }
    $map->initialize($param);
    $c->render(text => $map->svg, format => 'svg');
  } else {
    $c->render(template => 'edit', map => Mapper::example());
  }
};

any '/edit' => sub {
  my $c = shift;
  my $map = $c->param('map') || Mapper::example();
  $c->render(map => $map);
};

any '/render' => sub {
  my $c = shift;
  my $map;
  if ($c->param('type') and $c->param('type') eq 'square') {
    $map = new Mapper::Square;
  } else {
    $map = new Mapper::Hex;
  }
  $map->initialize($c->param('map'));
  $c->render(text => $map->svg, format => 'svg');
};

get '/:type/redirect' => sub {
  my $self = shift;
  my $type = $self->param('type');
  $self->redirect_to($self->url_for($type . "random")->query(seed => time));
} => 'redirect';

# alias for /smale
get '/random' => sub {
  my $c = shift;
  my $bw = $c->param('bw');
  my $width = $c->param('width');
  my $height = $c->param('height');
  $c->render(template => 'edit', map => Smale::generate_map($bw, $width, $height));
};

get '/smale' => sub {
  my $c = shift;
  my $bw = $c->param('bw');
  my $width = $c->param('width');
  my $height = $c->param('height');
  if ($c->stash('format')||'' eq 'txt') {
    $c->render(text => Smale::generate_map(undef, $width, $height));
  } else {
    $c->render(template => 'edit',
	       map => Smale::generate_map($bw, $width, $height));
  }
};

get '/smale/random' => sub {
  my $c = shift;
  my $bw = $c->param('bw');
  my $width = $c->param('width');
  my $height = $c->param('height');
  my $svg = Mapper::Hex->new()
      ->initialize(Smale::generate_map($bw, $width, $height))
      ->svg();
  $c->render(text => $svg, format => 'svg');
};

get '/smale/random/text' => sub {
  my $c = shift;
  my $bw = $c->param('bw');
  my $width = $c->param('width');
  my $height = $c->param('height');
  my $text = Smale::generate_map($bw, $width, $height);
  $c->render(text => $text, format => 'txt');
};

sub alpine_map {
  my $c = shift;
  # must be able to override this for the documentation
  my $step = shift // $c->param('step');
  # need to compute the seed here so that we can send along the URL
  my $seed = $c->param('seed') || int(rand(1000000000));
  my $url = $c->url_with('alpinedocument')->query({seed => $seed})->to_abs;
  my @params = ($c->param('width'),
		$c->param('height'),
		$c->param('steepness'),
		$c->param('peaks'),
		$c->param('peak'),
		$c->param('bumps'),
		$c->param('bump'),
		$c->param('bottom'),
		$c->param('arid'),
		$seed,
		$url,
		$step,
      );
  my $type = $c->param('type') // 'hex';
  if ($type eq 'hex') {
    return Schroeder::Hex->new()->generate_map(@params);
  } else {
    return Schroeder::Square->new()->generate_map(@params);
  }
}

get '/alpine' => sub {
  my $c = shift;
  my $map = alpine_map($c);
  if ($c->stash('format') || '' eq 'txt') {
    $c->render(text => $map);
  } else {
    $c->render(template => 'edit', map => $map);
  }
};

get '/alpine/random' => sub {
  my $c = shift;
  my $map = alpine_map($c);
  my $type = $c->param('type') // 'hex';
  my $mapper;
  if ($type eq 'hex') {
    $mapper = Mapper::Hex->new();
  } else {
    $mapper = Mapper::Square->new();
  }
  my $svg = $mapper->initialize($map)->svg;
  $c->render(text => $svg, format => 'svg');
};

get '/alpine/random/text' => sub {
  my $c = shift;
  my $map = alpine_map($c);
  $c->render(text => $map, format => 'txt');
};

get '/alpine/document' => sub {
  my $c = shift;
  # prepare a map for every step
  my @maps;
  my $type = $c->param('type') || 'hex';
  # use the same seed for all the calls
  my $seed = $c->param('seed');
  $seed = $c->param('seed' => int(rand(1000000000))) unless defined $seed;
  for my $step (1 .. 15) {
    my $map = alpine_map($c, $step);
    my $mapper;
    if ($type eq 'hex') {
      $mapper = Mapper::Hex->new();
    } else {
      $mapper = Mapper::Square->new();
    }
    my $svg = $mapper->initialize($map)->svg;
    $svg =~ s/<\?xml version="1.0" encoding="UTF-8" standalone="no"\?>\n//g;
    push(@maps, $svg);
  };
  $c->stash("maps" => \@maps);

  # the documentation needs all the defaults of Schroeder::generate_map (but
  # we'd like to use a smaller map because it is so slow)
  my $width = $c->param('width') // 20;
  my $height = $c->param('height') // 5; # instead of 10
  my $steepness = $c->param('steepness') // 3;
  my $peaks = $c->param('peaks') // int($width * $height / 40);
  my $peak = $c->param('peak') // 10;
  my $bumps = $c->param('bumps') // int($width * $height / 40);
  my $bump = $c->param('bump') // 2;
  my $bottom = $c->param('bottom') // 0;
  my $arid = $c->param('arid') // 2;

  $c->render(template => 'alpine_document',
	     seed => $seed,
	     width => $width,
	     height => $height,
	     steepness => $steepness,
	     peaks => $peaks,
	     peak => $peak,
	     bumps => $bumps,
	     bump => $bump,
	     bottom => $bottom,
	     arid => $arid);
};

get '/alpine/parameters' => sub {
  my $c = shift;
  $c->render(template => 'alpine_parameters');
};

sub gridmapper_map {
  my $c = shift;
  my $seed = $c->param('seed') || int(rand(1000000000));
  my $pillars = $c->param('pillars') // 1;
  srand($seed);
  return Gridmapper->new()->generate_map($pillars);
}

get '/gridmapper' => sub {
  my $c = shift;
  my $map = gridmapper_map($c);
  if ($c->stash('format') || '' eq 'txt') {
    $c->render(text => $map);
  } else {
    $c->render(template => 'edit', map => $map);
  }
};

get '/gridmapper/random' => sub {
  my $c = shift;
  my $map = gridmapper_map($c);
  my $mapper = Mapper::Square->new();
  my $svg = $mapper->initialize($map)->svg;
  $c->render(text => $svg, format => 'svg');
};

get '/gridmapper/random/text' => sub {
  my $c = shift;
  my $map = gridmapper_map($c);
  $c->render(text => $map, format => 'txt');
};

get '/source' => sub {
  my $c = shift;
  seek(DATA,0,0);
  local $/ = undef;
  $c->render(text => <DATA>, format => 'txt');
};

get '/help' => sub {
  my $c = shift;

  seek(DATA,0,0);
  local $/ = undef;
  my $pod = <DATA>;
  $pod =~ s/\$contrib/$contrib/g;
  my $parser = Pod::Simple::HTML->new;
  $parser->html_header_after_title('');
  $parser->html_header_before_title('');
  $parser->title_prefix('<!--');
  $parser->title_postfix('-->');
  my $html;
  $parser->output_string(\$html);
  $parser->parse_string_document($pod);

  my $dom = Mojo::DOM->new($html);
  for my $pre ($dom->find('pre')->each) {
    my $map = $pre->text;
    $map =~ s/^    //mg;
    next if $map =~ /^perl/; # how to call it
    my $url = $c->url_for('render')->query(map => $map);
    $pre->replace("<pre>" . xml_escape($map) . "</pre>\n"
		  . qq{<p class="example"><a href="$url">Render this example</a></p>});
  }

  $c->render(html => $dom);
};

app->start;

__DATA__

=encoding utf8

=head1 Text Mapper

The script parses a text description of a hex map and produces SVG output. Use
your browser to view SVG files and use Inkscape to edit them.

Here's a small example:

    grass attributes fill="green"
    0101 grass

We probably want lighter colors.

    grass attributes fill="#90ee90"
    0101 grass

First, we defined the SVG attributes of a hex B<type> and then we
listed the hexes using their coordinates and their type. Adding more
types and extending the map is easy:

    grass attributes fill="#90ee90"
    sea attributes fill="#afeeee"
    0101 grass
    0102 sea
    0201 grass
    0202 sea

You might want to define more SVG attributes such as a border around
each hex:

    grass attributes fill="#90ee90" stroke="black" stroke-width="1px"
    0101 grass

The attributes for the special type B<default> will be used for the
hex layer that is drawn on top of it all. This is where you define the
I<border>.

    default attributes fill="none" stroke="black" stroke-width="1px"
    grass attributes fill="#90ee90"
    sea attributes fill="#afeeee"
    0101 grass
    0102 sea
    0201 grass
    0202 sea

You can define the SVG attributes for the B<text> in coordinates as
well.

    text font-family="monospace" font-size="10pt"
    default attributes fill="none" stroke="black" stroke-width="1px"
    grass attributes fill="#90ee90"
    sea attributes fill="#afeeee"
    0101 grass
    0102 sea
    0201 grass
    0202 sea

You can provide a text B<label> to use for each hex:

    text font-family="monospace" font-size="10pt"
    default attributes fill="none" stroke="black" stroke-width="1px"
    grass attributes fill="#90ee90"
    sea attributes fill="#afeeee"
    0101 grass
    0102 sea
    0201 grass "promised land"
    0202 sea

To improve legibility, the SVG output gives you the ability to define an "outer
glow" for your labels by printing them twice and using the B<glow> attributes
for the one in the back. In addition to that, you can use B<label> to control
the text attributes used for these labels. If you append a number to the label,
it will be used as the new font-size.

    text font-family="monospace" font-size="10pt"
    label font-family="sans-serif" font-size="12pt"
    glow fill="none" stroke="white" stroke-width="3pt"
    default attributes fill="none" stroke="black" stroke-width="1px"
    grass attributes fill="#90ee90"
    sea attributes fill="#afeeee"
    0101 grass
    0102 sea
    0201 grass "promised land"
    0202 sea "deep blue sea" 20

You can define SVG B<path> elements to use for your map. These can be
independent of a type (such as an icon for a settlement) or they can
be part of a type (such as a bit of grass).

Here, we add a bit of grass to the appropriate hex type:

    text font-family="monospace" font-size="10pt"
    label font-family="sans-serif" font-size="12pt"
    glow fill="none" stroke="white" stroke-width="3pt"
    default attributes fill="none" stroke="black" stroke-width="1px"
    grass attributes fill="#90ee90"
    grass path attributes stroke="#458b00" stroke-width="5px"
    grass path M -20,-20 l 10,40 M 0,-20 v 40 M 20,-20 l -10,40
    sea attributes fill="#afeeee"
    0101 grass
    0102 sea
    0201 grass "promised land"
    0202 sea "deep blue sea" 20

Here, we add a settlement. The village doesn't have type attributes (it never
says C<village attributes>) and therefore it's not a hex type.

    text font-family="monospace" font-size="10pt"
    label font-family="sans-serif" font-size="12pt"
    glow fill="none" stroke="white" stroke-width="3pt"
    default attributes fill="none" stroke="black" stroke-width="1px"
    grass attributes fill="#90ee90"
    grass path attributes stroke="#458b00" stroke-width="5px"
    grass path M -20,-20 l 10,40 M 0,-20 v 40 M 20,-20 l -10,40
    village path attributes fill="none" stroke="black" stroke-width="5px"
    village path M -40,-40 v 80 h 80 v -80 z
    sea attributes fill="#afeeee"
    0101 grass
    0102 sea
    0201 grass village "Beachton"
    0202 sea "deep blue sea" 20

As you can see, you can have multiple types per coordinate, but
obviously only one of them should have the "fill" property (or they
must all be somewhat transparent).

As we said above, the village is an independent shape. As such, it also gets the
glow we defined for text. In our example, the glow has a stroke-width of 3pt and
the village path has a stroke-width of 5px which is why we can't see it. If had
used a thinner stroke, we would have seen a white outer glow. Here's the same
example with a 1pt stroke-width for the village.

    text font-family="monospace" font-size="10pt"
    label font-family="sans-serif" font-size="12pt"
    glow fill="none" stroke="white" stroke-width="3pt"
    default attributes fill="none" stroke="black" stroke-width="1px"
    grass attributes fill="#90ee90"
    grass path attributes stroke="#458b00" stroke-width="5px"
    grass path M -20,-20 l 10,40 M 0,-20 v 40 M 20,-20 l -10,40
    village path attributes fill="none" stroke="black" stroke-width="1pt"
    village path M -40,-40 v 80 h 80 v -80 z
    sea attributes fill="#afeeee"
    0101 grass
    0102 sea
    0201 grass village "Beachton"
    0202 sea "deep blue sea" 20

You can also have lines connecting hexes. In order to better control the flow of
these lines, you can provide multiple hexes through which these lines must pass.
You can append a label to these, too. These lines can be used for borders,
rivers or roads, for example.

    text font-family="monospace" font-size="10pt"
    label font-family="sans-serif" font-size="12pt"
    glow fill="none" stroke="white" stroke-width="3pt"
    default attributes fill="none" stroke="black" stroke-width="1px"
    grass attributes fill="#90ee90"
    grass path attributes stroke="#458b00" stroke-width="5px"
    grass path M -20,-20 l 10,40 M 0,-20 v 40 M 20,-20 l -10,40
    village path attributes fill="none" stroke="black" stroke-width="5px"
    village path M -40,-40 v 80 h 80 v -80 z
    sea attributes fill="#afeeee"
    0101 grass
    0102 sea
    0201 grass village "Beachton"
    0202 sea "deep blue sea" 20
    border path attributes stroke="red" stroke-width="15" stroke-opacity="0.5" fill-opacity="0"
    0002-0200 border "The Wall"
    road path attributes stroke="black" stroke-width="3" fill-opacity="0" stroke-dasharray="10 10"
    0000-0301 road

=head3 Include a Library

Since these definitions get unwieldy, require a lot of work (the path
elements), and to encourage reuse, you can use the B<include>
statement with an URL.

    include $contrib/default.txt
    0102 sand
    0103 sand
    0201 sand
    0202 jungle "oasis"
    0203 sand
    0302 sand
    0303 sand

You can find more files ("libraries") to include in the C<contrib>
directory:
L<https://alexschroeder.ch/cgit/hex-mapping/tree/contrib>.

=head3 Large Areas

If you want to surround a piece of land with a round shore line, a
forest with a large green shadow, you can achieve this using a line
that connects to itself. These "closed" lines can have C<fill> in
their path attributes. In the following example, the oasis is
surrounded by a larger green area.

    include $contrib/default.txt
    0102 sand
    0103 sand
    0201 sand
    0203 sand
    0302 sand
    0303 sand
    0102-0201-0302-0303-0203-0103-0102 green
    green path attributes fill="#9acd32"
    0202 jungle "oasis"

Confusingly, the "jungle path attributes" are used to draw the palm
tree, so we cannot use it do define the area around the oasis. We need
to define the green path attributes in order to do that.

I<Order is important>: First we draw the sand, then the green area,
then we drop a jungle on top of the green area.

=head2 Random

There's a button to generate a random landscape based on the algorithm
developed by Erin D. Smale. See
L<http://www.welshpiper.com/hex-based-campaign-design-part-1/> and
L<http://www.welshpiper.com/hex-based-campaign-design-part-2/> for
more information. The output uses the I<Gnomeyland> icons by Gregory
B. MacKenzie. These are licensed under the Creative Commons
Attribution-ShareAlike 3.0 Unported License. To view a copy of this
license, visit L<http://creativecommons.org/licenses/by-sa/3.0/>.

If you're curious: (11,11) is the starting hex.

=head2 SVG

You can define shapes using arbitrary SVG. Your SVG will end up in the
B<defs> section of the SVG output. You can then refer to the B<id>
attribute in your map definition. For the moment, all your SVG needs to
fit on a single line.

    <circle id="thorp" fill="#ffd700" stroke="black" stroke-width="7" cx="0" cy="0" r="15"/>
    0101 thorp

Shapes can include each other:

    <circle id="settlement" fill="#ffd700" stroke="black" stroke-width="7" cx="0" cy="0" r="15"/>
    <path id="house" stroke="black" stroke-width="7" d="M-15,0 v-50 m-15,0 h60 m-15,0 v50 M0,0 v-37"/>
    <use id="thorp" xlink:href="#settlement" transform="scale(0.6)"/>
    <g id="village" transform="scale(0.6), translate(0,40)"><use xlink:href="#house"/><use xlink:href="#settlement"/></g>
    0101 thorp
    0102 village

When creating new shapes, remember the dimensions of the hex. Your shapes must
be centered around (0,0). The width of the hex is 200px, the height of the hex
is 100 √3 = 173.2px. A good starting point would be to keep it within (-50,-50)
and (50,50).

=head2 Other

You can add even more arbitrary SVG using the B<other> keyword. This
keyword can be used multiple times.

    grass attributes fill="#90ee90"
    0101 grass
    0201 grass
    0302 grass
    other <text x="150" y="20" font-size="40pt" transform="rotate(30)">Tundra of Sorrow</text>

The B<other> keyword causes the item to be added to the end of the
document. It can be used for frames and labels that are not connected
to a single hex.

You can make labels link to web pages using the B<url> keyword.

    grass attributes fill="#90ee90"
    0101 grass "Home"
    url https://campaignwiki.org/wiki/NameOfYourWiki/

This will make the label X link to
C<https://campaignwiki.org/wiki/NameOfYourWiki/X>. You can also use
C<%s> in the URL and then this placeholder will be replaced with the
(URL encoded) label.

=head2 License

This program is copyright (C) 2007-2019 Alex Schroeder <alex@gnu.org>.

This program is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or (at
your option) any later version.

This program is distributed in the hope that it will be useful, but
WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU
General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program. If not, see L<http://www.gnu.org/licenses/>.

The maps produced by the program are obviously copyrighted by I<you>,
the author. If you're using SVG icons, these I<may> have a separate
license. Thus, if you produce a map using the I<Gnomeyland> icons by
Gregory B. MacKenzie, the map is automatically licensed under the
Creative Commons Attribution-ShareAlike 3.0 Unported License. To view
a copy of this license, visit
L<http://creativecommons.org/licenses/by-sa/3.0/>.

You can add arbitrary SVG using the B<license> keyword (without a
tile). This is what the Gnomeyland library does, for example.

    grass attributes fill="#90ee90"
    0101 grass
    license <text>Public Domain</text>

There can only be I<one> license keyword. If you use multiple
libraries or want to add your own name, you will have to write your
own.

There's a 50 pixel margin around the map, here's how you might
conceivably use it for your own map that uses the I<Gnomeyland> icons
by Gregory B. MacKenzie:

    grass attributes fill="#90ee90"
    0101 grass
    0201 grass
    0301 grass
    0401 grass
    0501 grass
    license <text x="50" y="-33" font-size="15pt" fill="#999999">Copyright Alex Schroeder 2013. <a style="fill:#8888ff" xlink:href="http://www.busygamemaster.com/art02.html">Gnomeyland Map Icons</a> Copyright Gregory B. MacKenzie 2012.</text><text x="50" y="-15" font-size="15pt" fill="#999999">This work is licensed under the <a style="fill:#8888ff" xlink:href="http://creativecommons.org/licenses/by-sa/3.0/">Creative Commons Attribution-ShareAlike 3.0 Unported License</a>.</text>

Unfortunately, it all has to go on a single line.

=head2 Examples

=head3 Default

Source of the map:
L<http://themetalearth.blogspot.ch/2011/03/opd-entry.html>

Example data:
L<$contrib/forgotten-depths.txt>

Library:
L<$contrib/default.txt>

Result:
L<https://campaignwiki.org/text-mapper?map=include+$contrib/forgotten-depths.txt>

=head3 Gnomeyland

Example data:
L<$contrib/gnomeyland-example.txt>

Library:
L<$contrib/gnomeyland.txt>

Result:
L<https://campaignwiki.org/text-mapper?map=include+$contrib/gnomeyland-example.txt>

=head3 Traveller

Example:
L<$contrib/traveller-example.txt>

Library:
L<$contrib/traveller.txt>

Result:
L<https://campaignwiki.org/text-mapper?map=include+$contrib/traveller-example.txt>

=head3 Dungeons

Example:
L<$contrib/gridmapper-example.txt>

Library:
L<$contrib/gridmapper.txt>

Result:
L<https://campaignwiki.org/text-mapper?type=square&map=include+$contrib/gridmapper-example.txt>

=head2 Configuration

As a Mojolicious application, it will read a config file called
F<text-mapper.conf> in the same directory, if it exists. As the default log
level is 'warn', one use of the config file is to change the log level using
the C<loglevel> key.

The libraries are loaded from the F<contrib> URL. You can change the default
using the C<contrib> key. This is necessary when you want to develop locally,
for example.

    {
      loglevel => 'debug',
      contrib => 'file://contrib',
    };

=head2 Command Line

You can call the script from the command line. The B<render> command reads a map
description from STDIN and prints it to STDOUT.

    perl text-mapper.pl render < contrib/forgotten-depths.txt > forgotten-depths.svg

The B<random> command prints a random map description to STDOUT.

    perl text-mapper.pl random > map.txt

Thus, you can pipe the random map in order to render it:

    perl text-mapper.pl random | perl text-mapper.pl render > map.svg

You can read this documentation in a text terminal, too:

    pod2text text-mapper.pl

Alternatively:

    perl text-mapper.pl get /help | w3m -T text/html

=cut


@@ help.html.ep
% layout 'default';
% title 'Text Mapper: Help';
<%== $html %>


@@ edit.html.ep
% layout 'default';
% title 'Text Mapper';
<h1>Text Mapper</h1>
<p>Submit your text desciption of the map.</p>
%= form_for render => (method => 'POST') => begin
%= text_area map => (cols => 60, rows => 15) => begin
<%= $map =%>
% end

<p>
%= radio_button type => 'hex', id => 'hex', checked => undef
%= label_for hex => 'Hex'
%= radio_button type => 'square', id => 'square'
%= label_for square => 'Square'

<p>
%= submit_button
</p>
%= end

<p>
<%= link_to smale => begin %>Random<% end %>
will generate map data based on Erin D. Smale's <em>Hex-Based Campaign Design</em>
(<a href="http://www.welshpiper.com/hex-based-campaign-design-part-1/">Part 1</a>,
<a href="http://www.welshpiper.com/hex-based-campaign-design-part-2/">Part 2</a>).
You can also generate a random map
<%= link_to url_for('smale')->query(bw => 1) => begin %>with no background colors<% end %>.
Click the submit button to generate the map itself. Or just keep reloading
<%= link_to smalerandom => begin %>this link<% end %>.
You'll find the map description in a comment within the SVG file.
</p>
%= form_for smale => begin
<table>
<tr><td>Width:</td><td>
%= number_field width => 20, min => 5, max => 99
</td></tr><tr><td>Height:</td><td>
%= number_field height => 10, min => 5, max => 99
</td></tr></table>
%= submit_button
% end
<p>
<%= link_to alpine => begin %>Alpine<% end %> will generate map data based on Alex
Schroeder's algorithm that's trying to recreate a medieval Swiss landscape, with
no info to back it up, whatsoever. See it
<%= link_to url_for('alpinedocument')->query(height => 5) => begin %>documented<% end %>.
Click the submit button to generate the map itself. Or just keep reloading
<%= link_to alpinerandom => begin %>this link<% end %>.
You'll find the map description in a comment within the SVG file.
</p>
%= form_for alpine => begin
<table>
<tr><td>Width:</td><td>
%= number_field width => 20, min => 5, max => 99
</td><td>Bottom:</td><td>
%= number_field bottom => 0, min => 0, max => 10
</td><td>Peaks:</td><td>
%= number_field peaks => 5, min => 0, max => 100
</td><td>Bumps:</td><td>
%= number_field bumps => 2, min => 0, max => 100
</td></tr><tr><td>Height:</td><td>
%= number_field height => 10, min => 5, max => 99
</td><td>Steepness:</td><td>
%= number_field steepness => 3, min => 1, max => 6
</td><td>Peak:</td><td>
%= number_field peak => 10, min => 7, max => 10
</td><td>Bump:</td><td>
%= number_field bump => 2, min => 1, max => 2
</td></tr><tr><td>Arid:</td><td>
%= number_field arid => 2, min => 0, max => 2
</td><td><td>
</td><td></td><td>
</td></tr></table>
<p>
See the <%= link_to alpineparameters => begin %>documentation<% end %> for an
explanation of what these parameters do.
<p>
%= radio_button type => 'hex', id => 'hex', checked => undef
%= label_for hex => 'Hex'
%= radio_button type => 'square', id => 'square'
%= label_for square => 'Square'
</p>
%= submit_button
% end
<p>
<%= link_to url_for('gridmapper')->query(type => 'square') => begin%>Gridmapper<% end %>
will generate dungeon map data based on geomorph sketches by Robin Green. Or
just keep reloading <%= link_to gridmapperrandom => begin %>this link<% end %>.
%= form_for gridmapper => begin
<p>
<label>
%= check_box pillars => 0
No rooms with pillars
</label>
%= hidden_field type => 'square'
<p>
%= submit_button
% end

@@ render.svg.ep


@@ alpine_parameters.html.ep
% layout 'default';
% title 'Alpine Parameters';
<h1>Alpine Parameters</h1>

<p>
This page explains what the parameters for the <em>Alpine</em> map generation
will do.
</p>
<p>
The parameters <strong>width</strong> and <strong>height</strong> determine how
big the map is.
</p>
<p>
Example:
<%= link_to url_for('alpinerandom')->query(height => 10, width => 15) => begin %>15×10 map<% end %>.
</p>
<p>
The number of peaks we start with is controlled by the <strong>peaks</strong>
parameter (default is 2½% of the hexes). Note that you need at least one peak in
order to get any land at all.
</p>
<p>
Examples:
<%= link_to url_for('alpinerandom')->query(height => 10, width => 15, peaks => 1) => begin %>lonely mountain<% end %>,
<%= link_to url_for('alpinerandom')->query(height => 10, width => 15, peaks => 2) => begin %>twin peaks<% end %>,
<%= link_to url_for('alpinerandom')->query(height => 10, width => 15, peaks => 15) => begin %>here be glaciers<% end %>
</p>
<p>
The number of bumps we start with is controlled by the <strong>bumps</strong>
parameter (default is 1% of the hexes). These are secondary hills and hollows.
</p>
<p>
Examples:
<%= link_to url_for('alpinerandom')->query(height => 10, width => 15, peaks => 1, bumps => 0) => begin %>lonely mountain, no bumps<% end %>,
<%= link_to url_for('alpinerandom')->query(height => 10, width => 15, peaks => 1, bumps => 4) => begin %>lonely mountain and four bumps<% end %>
</p>
<p>
When creating elevations, we surround each hex with a number of other hexes at
one altitude level lower. The number of these surrounding lower levels is
controlled by the <strong>steepness</strong> parameter (default 3). Lower means
steeper. Floating points are allowed. Please note that the maximum numbers of
neighbors considered is the 6 immediate neighbors and the 12 neighbors one step
away.
</p>
<p>
Examples:
<%= link_to url_for('alpinerandom')->query(height => 10, width => 15, steepness => 0) => begin %>ice needles map<% end %>,
<%= link_to url_for('alpinerandom')->query(height => 10, width => 15, steepness => 2) => begin %>steep mountains map<% end %>,
<%= link_to url_for('alpinerandom')->query(height => 10, width => 15, steepness => 4) => begin %>big mountains map<% end %>
</p>
<p>
The sea level is set to altitude 0. That's how you sometimes get a water hex at
the edge of the map. You can simulate global warming and set it to something
higher using the <strong>bottom</strong> parameter.
</p>
<p>
Example:
<%= link_to url_for('alpinerandom')->query(height => 10, width => 15, steepness => 2, bottom => 5) => begin %>steep mountains and higher water level map<% end %>
</p>
<p>
You can also control how high the highest peaks will be using the
<strong>peak</strong> parameter (default 10). Note that nothing special happens
to a hex with an altitude above 10. It's still mountain peaks. Thus, setting the
parameter to something higher than 10 just makes sure that there will be a lot
of mountain peaks.
</p>
<p>
Examples:
<%= link_to url_for('alpinerandom')->query(height => 10, width => 15, peak => 11) => begin %>big mountains<% end %>,
<%= link_to url_for('alpinerandom')->query(height => 10, width => 15, steepness => 3, bottom => 3, peak => 8) => begin %>old country<% end %>
</p>
<p>
You can also control how high the extra bumps will be using the
<strong>bump</strong> parameter (default 2).
</p>
<p>
Examples:
<%= link_to url_for('alpinerandom')->query(height => 10, width => 15, peaks => 1, bump => 1) => begin %>small bumps<% end %>,
<%= link_to url_for('alpinerandom')->query(height => 10, width => 15, peaks => 1, bump => 2) => begin %>bigger bumps<% end %>
</p>
<p>
You can also control forest growth (as opposed to grassland) by using the
<strong>arid</strong> parameter (default 2). That's how many hexes surrounding a
river hex will grow forests. Smaller means more arid and thus more grass.
Fractions are allowed. Thus, 0.5 means half the river hexes will have forests
grow to their neighbouring hexes.
</p>
<p>
Examples:
<%= link_to url_for('alpinerandom')->query(height => 10, width => 15, peaks => 2, stepness => 2, arid => 2) => begin %>fewer, steeper mountains<% end %>,
<%= link_to url_for('alpinerandom')->query(height => 10, width => 15, peaks => 2, stepness => 2, arid => 1) => begin %>less forest<% end %>,
<%= link_to url_for('alpinerandom')->query(height => 10, width => 15, peaks => 2, stepness => 2, arid => 0) => begin %>very arid<% end %>
</p>


@@ alpine_document.html.ep
% layout 'default';
% title 'Alpine Documentation';
<h1>Alpine Map: How does it get created?</h1>

<p>How do we get to the following map?
<%= link_to url_for('alpinedocument')->query(width => $width, height => $height, steepness => $steepness, peaks => $peaks, peak => $peak, bumps => $bumps, bump => $bump, bottom => $bottom, arid => $arid) => begin %>Reload<% end %>
to get a different one. If you like this particular map, bookmark
<%= link_to url_for('alpinerandom')->query(seed => $seed, width => $width, height => $height, steepness => $steepness, peaks => $peaks, peak => $peak, bumps => $bumps, bump => $bump, bottom => $bottom, arid => $arid) => begin %>this link<% end %>,
and edit it using
<%= link_to url_for('alpine')->query(seed => $seed, width => $width, height => $height, steepness => $steepness, peaks => $peaks, peak => $peak, bumps => $bumps, bump => $bump, bottom => $bottom, arid => $arid) => begin %>this link<% end %>,
</p>

%== $maps->[$#$maps]

<p>First, we pick <%= $peaks %> peaks and set their altitude to <%= $peak %>.
Then we loop down to 1 and for every hex we added in the previous run, we add
<%= $steepness %> neighbors at a lower altitude, if possible. We actually vary
steepness, so the steepness given is just an average. We'll also consider
neighbors one step away. If our random growth missed any hexes, we just copy the
height of a neighbor. If we can't find a suitable neighbor within a few tries,
just make a hole in the ground (altitude 0).</p>

<p>The number of peaks can be changed using the <em>peaks</em> parameter. Please
note that 0 <em>peaks</em> will result in no land mass.</p>

<p>The initial altitude of those peaks can be changed using the <em>peak</em>
parameter. Please note that a <em>peak</em> smaller than 7 will result in no
sources for rivers.</p>

<p>The number of adjacent hexes at a lower altitude can be changed using the
<em>steepness</em> parameter. Floating points are allowed. Please note that the
maximum numbers of neighbors considered is the 6 immediate neighbors and the 12
neighbors one step away.</p>

%== shift(@$maps)

<p>Next, we pick <%= $bumps %> bumps and shift their altitude by -<%= $bump %>,
and <%= $bumps %> bumps and shift their altitude by +<%= $bump %>. If the shift
is bigger than 1, then we shift the neighbours by one less.</p>

%== shift(@$maps)

<p>Mountains are the hexes at high altitudes: white mountains (altitude 10),
white mountain (altitude 9), light-grey mountain (altitude 8).</p>

%== shift(@$maps)

<p>We determine the flow of water by having water flow to one of the lowest
neighbors if possible. Water doesn't flow upward, and if there is already water
coming our way, then it won't flow back. It has reached a dead end.</p>

%== shift(@$maps)

<p>Any of the dead ends we found in the previous step are marked as lakes.
Anthing beneath an altitude of <%= $bottom %> is marked the same. This is
considered to be the sea level.</p>

%== shift(@$maps)

<p>We still need to figure out how to drain lakes. In order to do that, we start
"flooding" lakes, looking for a way to the edge of the map. If we're lucky, our
search will soon hit upon a sequence of arrows that leads to ever lower
altitudes and to the edge of the map. An outlet! We start with all the hexes
that don't have an arrow. For each one of those, we look at its neighbors. These
are our initial candidates. We keep expanding our list of candidates as we add
at neighbors of neighbors. At every step we prefer the lowest of these
candidates. Once we have reached the edge of the map, we backtrack and change
any arrows pointing the wrong way.</p>

%== shift(@$maps)

<p>We add bogs (altitude 7) if the water flows into a hex at the same altitude.
It is insufficiently drained. We use grey swamps to indicate this.</p>

%== shift(@$maps)

<p>We add a river sources high up in the mountains (altitudes 7 and 8), merging
them as appropriate. These rivers flow as indicated by the arrows. If the river
source is not a mountain (altitude 8) or a bog (altitude 7), then we place a
forested hill at the source (thus, they're all at altitude 7).</p>

%== shift(@$maps)

<p>Remember how the arrows were changed at some points such that rivers don't
always flow downwards. We're going to assume that in these situations, the
rivers have cut canyons into the higher lying ground and we'll add a little
shadow.</p>

%== shift(@$maps)

<p>Any hex <em>with a river</em> that flows towards a neighbor at the same
altitude is insufficiently drained. These are marked as swamps. The background
color of the swamp depends on the altitude: grey if altitude 6 and higher,
otherwise dark-grey.</p>

%== shift(@$maps)

<p>Wherever there is water and no swamp, forests will form. The exact type again
depends on the altitude: light green fir-forest (altitude 7 and higher), green
fir-forest (altitude 6), green forest (altitude 4–5), dark-green forest
(altitude 3 and lower). Once a forest is placed, it expands up to <%= $arid %> hexes
away, even if those hexes have no water flowing through them. You probably need
fewer peaks on your map to verify this (a <%= link_to
url_with('alpinerandom')->query({peaks => 1}) => begin %>lonely mountain<% end
%> map, for example).</p>

%== shift(@$maps)

<p>Any remaining hexes have no water nearby and are considered to be little more
arid. They get bushes, a hill (20% of the time at altitudes 3 or higher), or
some grass (60% of the time at altitudes 3 and lower). Higher up, these are
light grey (altitude 6–7), otherwise they are light green (altitude 5 and
below).</p>

%== shift(@$maps)

<p>Cliffs form wherever the drop is more than just one level of altitude.</p>

%== shift(@$maps)

<p>Wherenver there is forest, settlements will be built. These reduce the
density of the forest. There are three levels of settlements: thorps, villages
and towns.</p>

<table>
<tr><th>Settlement</th><th>Forest</th><th>Number</th><th>Minimum Distance</th></tr>
<tr><td>Thorp</td><td>fir-forest, forest</td><td class="numeric">10%</td><td class="numeric">2</td></tr>
<tr><td>Village</td><td>forest &amp; river</td><td class="numeric">5%</td><td class="numeric">5</td></tr>
<tr><td>Town</td><td>forest &amp; river</td><td class="numeric">2½%</td><td class="numeric">10</td></tr>
<tr><td>Law</td><td>white mountain</td><td class="numeric">2½%</td><td class="numeric">10</td></tr>
<tr><td>Chaos</td><td>swamp</td><td class="numeric">2½%</td><td class="numeric">10</td></tr>
</table>

%== shift(@$maps)

<p>Trails connect every settlement to any neighbor that is one or two hexes
away. If no such neighbor can be found, we try to find neighbors that are three
hexes away.</p>

%== shift(@$maps)

@@ layouts/default.html.ep
<!DOCTYPE html>
<html>
<head>
<title><%= title %></title>
%= stylesheet '/text-mapper.css'
%= stylesheet begin
body {
  padding: 1em;
  font-family: "Palatino Linotype", "Book Antiqua", Palatino, serif;
}
textarea {
  width: 100%;
}
table {
  padding-bottom: 1em;
}
td, th {
  padding-right: 0.5em;
}
.example {
  font-size: smaller;
}
.numeric {
  text-align: center;
}
% end
<meta name="viewport" content="width=device-width">
</head>
<body>
<%= content %>
<hr>
<p>
<a href="https://campaignwiki.org/text-mapper">Text Mapper</a>&#x2003;
<%= link_to 'Help' => 'help' %>&#x2003;
<%= link_to 'Source' => 'source' %>&#x2003;
<a href="https://alexschroeder.ch/cgit/hex-mapping/about/#text-mapper">Git</a>&#x2003;
<a href="https://alexschroeder.ch/wiki/Contact">Alex Schroeder</a>
</body>
</html>
