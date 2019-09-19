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

1;
