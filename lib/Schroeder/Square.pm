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

1;
