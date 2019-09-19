package Mapper::Square;
use Line::Square;

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

1;
