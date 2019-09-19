package Mapper::Hex;
use Line::Hex;

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

1;
