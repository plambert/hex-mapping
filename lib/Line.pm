package Line;

use Class::Struct;

struct Line => {
		id => '$',
		points => '@',
		type => '$',
		label => '$',
		map => 'Mapper',
	       };

sub compute_missing_points {
  my $self = shift;
  my $i = 0;
  my $current = $self->points($i++);
  my @result = ($current);
  while ($self->points($i)) {
    $current = $self->one_step($current, $self->points($i));
    push(@result, $current);
    $i++ if $current->equal($self->points($i));
  }

  return @result;
}

sub partway {
  my ($self, $from, $to, $q) = @_;
  my ($x1, $y1) = $self->pixels($from);
  my ($x2, $y2) = $self->pixels($to);
  $q ||= 1;
  return $x1 + ($x2 - $x1) * $q, $y1 + ($y2 - $y1) * $q if wantarray;
  return sprintf("%.1f,%.1f", $x1 + ($x2 - $x1) * $q, $y1 + ($y2 - $y1) * $q);
}

sub svg {
  my $self = shift;
  my ($path, $current, $next, $closed);

  my @points = $self->compute_missing_points();
  if ($points[0]->equal($points[$#points])) {
    $closed = 1;
  }

  if ($closed) {
    for my $i (0 .. $#points - 1) {
      $current = $points[$i];
      $next = $points[$i+1];
      if (!$path) {
	my $a = $self->partway($current, $next, 0.3);
	my $b = $self->partway($current, $next, 0.5);
	my $c = $self->partway($points[$#points-1], $current, 0.7);
	my $d = $self->partway($points[$#points-1], $current, 0.5);
	$path = "M$d C$c $a $b";
      } else {
	# continue curve
	my $a = $self->partway($current, $next, 0.3);
	my $b = $self->partway($current, $next, 0.5);
	$path .= " S$a $b";
      }
    }
  } else {
    for my $i (0 .. $#points - 1) {
      $current = $points[$i];
      $next = $points[$i+1];
      if (!$path) {
	# line from a to b; control point a required for following S commands
	my $a = $self->partway($current, $next, 0.3);
	my $b = $self->partway($current, $next, 0.5);
	$path = "M$a C$b $a $b";
      } else {
	# continue curve
	my $a = $self->partway($current, $next, 0.3);
	my $b = $self->partway($current, $next, 0.5);
	$path .= " S$a $b";
      }
    }
    # end with a little stub
    $path .= " L" . $self->partway($current, $next, 0.7);
  }

  my $id = $self->id;
  my $type = $self->type;
  my $attributes = $self->map->path_attributes($type);
  my $data = qq{    <path id="$id" $attributes d="$path"/>\n};
  $data .= $self->debug($closed) if $debug;
  return $data;
}

sub svg_label {
  my ($self) = @_;
  return '' unless defined $self->label;
  my $id = $self->id;
  my $label = $self->label;
  my $attributes = $self->map->label_attributes || "";
  my $glow = $self->map->glow_attributes || "";
  my $url = $self->map->url;
  $url =~ s/\%s/url_encode($self->label)/e or $url .= url_encode($self->label) if $url;
  # default is left, but if the line goes from right to left, then "left" means "upside down"
  my $side = '';
  if ($self->points->[1]->x < $self->points->[0]->x
      or $#{$self->points} >= 2 and $self->points->[2]->x < $self->points->[0]->x) {
    $side = ' side="right"';
  }
  my $data = qq{    <g>\n};
  $data .= qq{      <text $attributes $glow><textPath$side href='#$id'>$label</textPath></text>\n>} if $glow;
  $data .= qq{      <a xlink:href="$url">} if $url;
  $data .= qq{      <text $attributes><textPath href='#$id'>$label</textPath></text>\n>};
  $data .= qq{      </a>} if $url;
  $data .= qq{    </g>\n};
  return $data;
}

sub debug {
  my ($self, $closed) = @_;
  my ($data, $current, $next);
  my @points = $self->compute_missing_points();
  for my $i (0 .. $#points - 1) {
    $current = $points[$i];
    $next = $points[$i+1];
    $data .= circle($self->pixels($current), 15, $i++);
    $data .= circle($self->partway($current, $next, 0.3), 3, 'a');
    $data .= circle($self->partway($current, $next, 0.5), 5, 'b');
    $data .= circle($self->partway($current, $next, 0.7), 3, 'c');
  }
  $data .= circle($self->pixels($next), 15, $#points);

  my ($x, $y) = $self->pixels($points[0]); $y += 30;
  $data .= "<text fill='#000' font-size='20pt' "
    . "text-anchor='middle' dominant-baseline='central' "
    . "x='$x' y='$y'>closed</text>"
      if $closed;

  return $data;
}

sub circle {
  my ($x, $y, $r, $i) = @_;
  my $data = "<circle fill='#666' cx='$x' cy='$y' r='$r'/>";
  $data .= "<text fill='#000' font-size='20pt' "
    . "text-anchor='middle' dominant-baseline='central' "
    . "x='$x' y='$y'>$i</text>" if $i;
  return "$data\n";
}

1;
