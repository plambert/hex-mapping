package Schroeder::Hex;
use POSIX;

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

1;
