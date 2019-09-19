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

1;
