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

1;
