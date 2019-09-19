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

1;
