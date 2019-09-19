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

1;
