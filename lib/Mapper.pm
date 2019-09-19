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

1;
