package Gridmapper;
use List::Util qw'shuffle none any';
use List::MoreUtils qw'pairwise';
use Class::Struct;

# Currently empty
struct Gridmapper => {};

# This is the meta grid for the geomorphs.
my @dungeon_dimensions = (3, 3);
# This is the grid for a particular geomorph.
my @room_dimensions = (5, 5);
# Add two tiles for the edges.
my $row = $dungeon_dimensions[0] * $room_dimensions[0] + 4;
my $col = $dungeon_dimensions[1] * $room_dimensions[1] + 4;
my $max = $row * $col - 1;
# (0,0) starts at the top left and goes rows before columns, like text.

sub generate_map {
  my $self = shift;
  my $pillars = shift;
  my $rooms = [map { generate_room($_, $pillars) } (1 .. 5)];
  my $shape = shape(scalar(@$rooms));
  my $tiles = add_rooms($rooms, $shape);
  $tiles = add_corridors($tiles, $shape);
  $tiles = add_doors($tiles);
  $tiles = add_stair($tiles);
  $tiles = fix_corners($tiles);
  $tiles = fix_pillars($tiles) if $pillars;
  my $text = to_text($tiles);
}

sub generate_room {
  my $num = shift;
  my $pillars = shift;
  my $r = rand();
  if ($r < 0.9) {
    return generate_random_room($num);
  } elsif ($r < 0.95 and $pillars) {
    return generate_pillar_room($num);
  } else {
    return generate_fancy_corner_room($num);
  }
}

sub generate_random_room {
  my $num = shift;
  # generate the tiles necessary for a single geomorph
  my @tiles;
  my @dimensions = (2 + int(rand(3)), 2 + int(rand(3)));
  my @start = pairwise { int(rand($b - $a)) } @dimensions, @room_dimensions;
  # $log->debug("New room starting at (@start) for dimensions (@dimensions)");
  for my $x ($start[0] .. $start[0] + $dimensions[0] - 1) {
    for my $y ($start[1] .. $start[1] + $dimensions[1] - 1) {
      $tiles[$x + $y * $room_dimensions[0]] = ["empty"];
    }
  }
  my $x = $start[0] + int($dimensions[0]/2);
  my $y = $start[1] + int($dimensions[1]/2);
  push(@{$tiles[$x + $y * $room_dimensions[0]]}, "\"$num\"");
  return \@tiles;
}

sub generate_fancy_corner_room {
  my $num = shift;
  my @tiles;
  my @dimensions = (3 + int(rand(2)), 3 + int(rand(2)));
  my @start = pairwise { int(rand($b - $a)) } @dimensions, @room_dimensions;
  # $log->debug("New room starting at (@start) for dimensions (@dimensions)");
  for my $x ($start[0] .. $start[0] + $dimensions[0] - 1) {
    for my $y ($start[1] .. $start[1] + $dimensions[1] - 1) {
      push(@{$tiles[$x + $y * $room_dimensions[0]]}, "empty");
      # $log->debug("$x $y @{$tiles[$x + $y * $room_dimensions[0]]}");
    }
  }
  my $type = rand() < 0.5 ? "arc" : "diagonal";
  $tiles[$start[0] + $start[1] * $room_dimensions[0]] = ["$type-se"];
  $tiles[$start[0] + $dimensions[0] + $start[1] * $room_dimensions[0] -1] = ["$type-sw"];
  $tiles[$start[0] + ($start[1] + $dimensions[1] - 1) * $room_dimensions[0]] = ["$type-ne"];
  $tiles[$start[0] + $dimensions[0] + ($start[1] + $dimensions[1] - 1) * $room_dimensions[0] - 1] = ["$type-nw"];
  my $x = $start[0] + int($dimensions[0]/2);
  my $y = $start[1] + int($dimensions[1]/2);
  push(@{$tiles[$x + $y * $room_dimensions[0]]}, "\"$num\"");
  return \@tiles;
}

sub generate_pillar_room {
  my $num = shift;
  my @tiles;
  my @dimensions = (3 + int(rand(2)), 3 + int(rand(2)));
  my @start = pairwise { int(rand($b - $a)) } @dimensions, @room_dimensions;
  # $log->debug("New room starting at (@start) for dimensions (@dimensions)");
  my $type = "|";
  for my $x ($start[0] .. $start[0] + $dimensions[0] - 1) {
    for my $y ($start[1] .. $start[1] + $dimensions[1] - 1) {
      if ($type eq "|" and ($x == $start[0] or $x == $start[0] + $dimensions[0] - 1)
	  or $type eq "-" and ($y == $start[1] or $y == $start[1] + $dimensions[1] - 1)) {
	push(@{$tiles[$x + $y * $room_dimensions[0]]}, "pillar");
      } else {
	push(@{$tiles[$x + $y * $room_dimensions[0]]}, "empty");
	# $log->debug("$x $y @{$tiles[$x + $y * $room_dimensions[0]]}");
      }
    }
  }
  my $x = $start[0] + int($dimensions[0]/2);
  my $y = $start[1] + int($dimensions[1]/2);
  push(@{$tiles[$x + $y * $room_dimensions[0]]}, "\"$num\"");
  return \@tiles;
}

sub one {
  return $_[int(rand(scalar @_))];
}

sub shape {
  # return an array of deltas to shift rooms around
  my $num = shift;
  my $shape = [];
  if ($num == 5) {
    $shape= one(
      # The Nine Forms of the Five Room Dungeon
      # https://gnomestew.com/the-nine-forms-of-the-five-room-dungeon/
      #
      # The Railroad
      #
      #       5        5     4--5         5--4
      #       |        |     |		     |
      #       4     3--4     3       5--4    3
      #       |     |        |          |    |
      # 1--2--3  1--2     1--2    1--2--3 1--2
      [[0, 2], [1, 2], [2, 2], [2, 1], [2, 0]],
      [[0, 2], [1, 2], [1, 1], [2, 1], [2, 0]],
      [[0, 2], [1, 2], [1, 1], [1, 0], [2, 0]],
      [[0, 2], [1, 2], [2, 2], [2, 1], [1, 1]],
      [[0, 2], [1, 2], [1, 1], [1, 0], [0, 0]],
      #
      # Note how whenever there is a non-linear connection, there is a an extra
      # element pointing to the "parent". This is necessary for all but the
      # railroads.
      #
      # Foglio's Snail
      #
      #    5  4
      #    |  |
      # 1--2--3
      [[0, 2], [1, 2], [2, 2], [2, 1], [1, 1, 1]],
      #
      # The Fauchard Fork
      #
      #    5       5
      #    |       |
      #    3--4 4--3 5--3--4
      #    |       |    |
      # 1--2    1--2 1--2
      [[0, 2], [1, 2], [1, 1], [2, 1], [1, 0, 2]],
      [[0, 2], [1, 2], [1, 1], [0, 1], [1, 0, 2]],
      [[0, 2], [1, 2], [1, 1], [2, 1], [0, 1, 2]],
      #
      # The Moose
      #
      #            4
      #	           |
      # 5     4 5  3
      # |     | |  |
      # 1--2--3 1--2
      [[0, 2], [1, 2], [2, 2], [2, 1], [0, 1, 0]],
      [[0, 2], [1, 2], [1, 1], [1, 0], [0, 1, 0]],
      #
      # The Paw
      #
      #    5
      #    |
      # 3--2--4
      #    |
      #    1
      [[1, 2], [1, 1], [0, 1], [2, 1, 1], [1, 0, 1]],
      #
      # The Arrow
      #
      #    3
      #	   |
      #    2
      #    |
      # 5--1--4
      [[1, 2], [1, 1], [1, 0], [2, 2, 0], [0, 2, 0]],
      #
      # The Cross
      #
      #    5
      #    |
      # 3--1--4
      #    |
      #    2
      [[1, 1], [1, 2], [0, 1, 0], [2, 1, 0], [1, 0, 0]],
      #
      # The Nose Ring
      #
      #    5--4  2--3--4
      #    |  |  |  |
      # 1--2--3  1--5
      # [[0, 2], [1, 2], [2, 2], [2, 1], [1, 1, 1, 3]],
      [[0, 2], [0, 1], [1, 1], [2, 1], [1, 2, 0, 2]],
	);
  }
  # $log->debug(join(", ", map { "[@$_]"} @$shape));
  my $r = rand;
  if ($r < 0.20) {
    # flip vertically
    $shape = [map{ $_->[1] = $dungeon_dimensions[1] - 1 - $_->[1]; $_ } @$shape];
    # $log->debug("flip vertically: " . join(", ", map { "[@$_]"} @$shape));
  } elsif ($r < 0.4) {
    # flip horizontally
    $shape = [map{ $_->[0] = $dungeon_dimensions[0] - 1 - $_->[0]; $_ } @$shape];
    # $log->debug("flip horizontally: " . join(", ", map { "[@$_]"} @$shape));
  } elsif ($r < 0.6) {
    # flip diagonally
    $shape = [map{ my $t = $_->[1]; $_->[1] = $_->[0]; $_->[0] = $t; $_ } @$shape];
    # $log->debug("flip diagonally: " . join(", ", map { "[@$_]"} @$shape));
  } elsif ($r < 0.8) {
    # flip diagonally
    $shape = [map{ $_->[0] = $dungeon_dimensions[0] - 1 - $_->[0];
		   $_->[1] = $dungeon_dimensions[1] - 1 - $_->[1];
		   $_ } @$shape];
    # $log->debug("flip both: " . join(", ", map { "[@$_]"} @$shape));
  }
  $log->error("No appropriate dungeon shape found") unless $shape;
  return $shape;
}

sub add_rooms {
  # Get the rooms and the deltas, draw it all on a big grid. Don't forget the
  # two-tile border around it all.
  my $rooms = shift;
  my $deltas = shift;
  my @tiles;
  pairwise {
    my $room = $a;
    my $delta = $b;
    # $log->debug("Draw room shifted by delta (@$delta)");
    # copy the room, shifted appropriately
    for my $x (0 .. $room_dimensions[0] - 1) {
      for my $y (0 .. $room_dimensions[0] - 1) {
	my $v = $tiles[$x + $delta->[0] * $room_dimensions[0] + 2
		       + ($y + $delta->[1] * $room_dimensions[1] + 2)
		       * $row]
	    = $room->[$x + $y * $room_dimensions[0]];
	# $log->debug(sprintf("%02d%02d (%d) %s", $x + $delta->[0] * $room_dimensions[0],
	# 		    $y + $delta->[1] * $room_dimensions[1],
	# 		    $x + $delta->[0] * $room_dimensions[0]
	# 		    + ($y + $delta->[1] * $room_dimensions[1]) * $row,
	# 		    join(" ", @$v))) if $v;
      }
    }
  } @$rooms, @$deltas;
  return \@tiles;
}

sub add_corridors {
  my $tiles = shift;
  my $shapes = shift;    # reference to the original
  my @shapes = @$shapes; # a copy that gets shorter
  my $from = shift(@shapes);
  my $delta;
  for my $to (@shapes) {
    if (@$to == 2) {
      # The default case is that the preceding shape is our parent. A simple
      # railroad!
      # $log->debug("from @$from to @$to");
      $tiles = add_corridor($tiles, $from, $to, get_delta($from, $to));
      $from = $to;
    } else {
      # In case the shapes are not connected in order, the parent shapes are
      # available as extra elements.
      for my $from (map { $shapes->[$_] } @$to[2 .. $#$to]) {
	# $log->debug(" from @$from to @$to");
	$tiles = add_corridor($tiles, $from, $to, get_delta($from, $to));
      }
    }
  }
  return $tiles;
}

sub get_delta {
  my $from = shift;
  my $to = shift;
  # Direction: north is minus an entire row, south is plus an entire row, east
  # is plus one, west is minus one. Return an array reference with three
  # elements: how to get the next element and how to get the two elements to the
  # left and right.
  if ($to->[0] < $from->[0]) {
    # $log->debug("west");
    return [-1, - $row, $row];
  } elsif ($to->[0] > $from->[0]) {
    # $log->debug("east");
    return [1, - $row, $row];
  } elsif ($to->[1] < $from->[1]) {
    # $log->debug("north");
    return [- $row, 1, -1];
  } elsif ($to->[1] > $from->[1]) {
    # $log->debug("south");
    return [$row, 1, -1];
  } else {
    $log->warn("unclear direction: bogus shape?");
  }
}

sub position_in {
  # Return a position in the big array corresponding to the midpoint in a room.
  # Don't forget the two-tile border.
  my $delta = shift;
  my $x = int($room_dimensions[0]/2) + 2;
  my $y = int($room_dimensions[1]/2) + 2;
  return $x + $delta->[0] * $room_dimensions[0]
      + ($y + $delta->[1] * $room_dimensions[1]) * $row;
}

sub add_corridor {
  # In the example below, we're going east from F to T. In order to make sure
  # that we also connect rooms in (0,0)-(1,1), we start one step earlier (1,2)
  # and end one step later (8,2).
  #
  #  0123456789
  # 0
  # 1
  # 2  F    T
  # 3
  # 4
  my $tiles = shift;
  my $from = shift;
  my $to = shift;
  # Delta has three elements: forward, left and right indexes.
  my $delta = shift;
  # Convert $from and $to to indexes into the tiles array.
  $from = position_in($from) - 2 * $delta->[0];
  $to = position_in($to) + 2 * $delta->[0];
  my $n = 0;
  my $contact = 0;
  my $started = 0;
  my @undo;
  # $log->debug("Checking $from-$to");
  while (not grep { $to == ($from + $_) } @$delta) {
    $from += $delta->[0];
    # contact is if we're on a room, or to the left or right of a room (but not in front of a room)
    $contact = any { something($tiles, $from, $_) } 0, $delta->[1], $delta->[2];
    if ($contact) {
      $started = 1;
      @undo = ();
    } else {
      push(@undo, $from);
    }
    $tiles->[$from] = ["empty"] if $started and not $tiles->[$from];
    last if $n++ > 20; # safety!
  }
  for (@undo) {
    $tiles->[$_] = undef;
  }
  return $tiles;
}

sub add_doors {
  my $tiles = shift;
  # Doors can be any tile that has three or four neighbours, including
  # diagonally:
  #
  # ▓▓   ▓▓
  # ▓▓▒▓ ▓▓▒▓
  #      ▓▓
  my @types = qw(door door door door door door secret secret archway concealed);
  # first two neighbours must be clear, the next two must be set, and one of the others must be set as well
  my %test = (n => [-1, 1, -$row, $row, -$row + 1, -$row - 1],
	      e => [-$row, $row, -1, 1, $row + 1, -$row + 1],
	      s => [-1, 1, -$row, $row, $row + 1, $row - 1],
	      w => [-$row, $row, -1, 1, $row - 1, -$row - 1]);
  my @doors;
  for my $here (shuffle 1 .. scalar(@$tiles) - 1) {
    for my $dir (shuffle qw(n e s w)) {
      if ($tiles->[$here]
	  and not something($tiles, $here, $test{$dir}->[0])
	  and not something($tiles, $here, $test{$dir}->[1])
	  and something($tiles, $here, $test{$dir}->[2])
	  and something($tiles, $here, $test{$dir}->[3])
	  and (something($tiles, $here, $test{$dir}->[4])
	       or something($tiles, $here, $test{$dir}->[5]))
	  and not doors_nearby($here, \@doors)) {
	$log->warn("$here content isn't 'empty'") unless $tiles->[$here]->[0] eq "empty";
	my $type = one(@types);
	my $variant = $dir;
	my $target = $here;
	# this makes sure doors are on top
	if ($dir eq "s") { $target += $row; $variant = "n"; }
	elsif ($dir eq "e") { $target += 1; $variant = "w"; }
	push(@{$tiles->[$target]}, "$type-$variant");
	push(@doors, $here);
      }
    }
  }
  return $tiles;
}

sub doors_nearby {
  my $here = shift;
  my $doors = shift;
  for my $door (@$doors) {
    return 1 if distance($door, $here) < 2;
  }
  return 0;
}

sub distance {
  my $from = shift;
  my $to = shift;
  my $dx = $to % $row - $from % $row;
  my $dy = int($to/$row) - int($from/$row);
  return sqrt($dx * $dx + $dy * $dy);
}

sub add_stair {
  my $tiles = shift;
  # find the middle using the label
  my $start;
  for my $one (0 .. scalar(@$tiles) - 1) {
    next unless $tiles->[$one];
    $start = $one;
    last if grep { $_ eq '"1"' } @{$tiles->[$one]};
  }
  # The first test refers to a tile that must be set to "empty" (where the stair
  # will end), all others must be undefined. Note that stairs are anchored at
  # the top end, and we're placing a stair that goes *down*. So what we're
  # looking for is the point (4,1) in the image below:
  #
  #   12345
  # 1 EE<<
  # 2 EE
  #
  # Remember, +1 is east, -1 is west, -$row is north, +$row is south. The anchor
  # point we're testing is already known to be undefined.
  my %test = (n => [-2 * $row,
		    -$row - 1, -$row, -$row + 1,
		    -1, +1,
		    +$row - 1, +$row, +$row + 1],
	      e => [+2,
		    -$row + 1, +1, +$row + 1,
		    -$row, +$row,
		    -$row - 1, -1, +$row - 1]);
  $test{s} = [map { -$_ } @{$test{n}}];
  $test{w} = [map { -$_ } @{$test{e}}];
  # First round: limit ourselves to stair positions close to the start.
  my %candidates;
  for my $here (shuffle 0 .. scalar(@$tiles) - 1) {
    next if $tiles->[$here];
    my $distance = distance($here, $start);
    $candidates{$here} = $distance if $distance <= 4;
  }
  # Second round: for each candidate, test stair placement and record the
  # distance of the landing to the start and the direction of every successful
  # stair.
  my $stair;
  my $stair_dir;
  my $stair_distance = $max;
  for my $here (sort {$a cmp $b} keys %candidates) {
    # push(@{$tiles->[$here]}, "red");
    for my $dir (shuffle qw(n e w s)) {
      my @test = @{$test{$dir}};
      my $first = shift(@test);
      if (# the first test is an empty tile: this the stair's landing
	  empty($tiles, $here, $first)
	  # and the stair is surrounded by empty space
	  and none { something($tiles, $here, $_) } @test) {
	my $distance = distance($here + $first, $start);
	if ($distance < $stair_distance) {
	  # $log->debug("Considering stair-$dir for $here ($distance)");
	  $stair = $here;
	  $stair_dir = $dir;
	  $stair_distance = $distance;
	}
      }
    }
  }
  if (defined $stair) {
    push(@{$tiles->[$stair]}, "stair-$stair_dir");
    return $tiles;
  }
  # $log->debug("Unable to place a regular stair, trying to place a spiral staircase");
  for my $here (shuffle 0 .. scalar(@$tiles) - 1) {
    next unless $tiles->[$here];
    if (# close by
	distance($here, $start) < 3
	# and the landing is empty (no statue, doors n or w)
	and @{$tiles->[$here]} == 1
	and $tiles->[$here]->[0] eq "empty"
	# and the landing to the south has no door n
	and not grep { /-n$/ } @{$tiles->[$here+$row]}
	# and the landing to the east has no door w
	and not grep { /-w$/ } @{$tiles->[$here+1]}) {
      $log->debug("Placed spiral stair at $here");
      $tiles->[$here]->[0] = "stair-spiral";
      return $tiles;
    }
  }
  $log->warn("Unable to place a stair!");
  return $tiles;
}

sub fix_corners {
  my $tiles = shift;
  my %look = (n => -$row, e => 1, s => $row, w => -1);
  for my $here (0 .. scalar(@$tiles) - 1) {
    for (@{$tiles->[$here]}) {
      if (/^(arc|diagonal)-(ne|nw|se|sw)$/) {
	my $dir = $2;
	# debug_neighbours($tiles, $here);
	if (substr($dir, 0, 1) eq "n" and $here + $row < $max and $tiles->[$here + $row] and @{$tiles->[$here + $row]}
	    or substr($dir, 0, 1) eq "s" and $here > $row and $tiles->[$here - $row] and @{$tiles->[$here - $row]}
	    or substr($dir, 1) eq "e" and $here > 0 and $tiles->[$here - 1] and @{$tiles->[$here - 1]}
	    or substr($dir, 1) eq "w" and $here < $max and $tiles->[$here + 1] and @{$tiles->[$here + 1]}) {
	  $_ = "empty";
	}
      }
    }
  }
  return $tiles;
}

sub fix_pillars {
  my $tiles = shift;
  my %test = (n => [-$row, -$row - 1, -$row + 1],
	      e => [1, 1 - $row, 1 + $row],
	      s => [$row, $row - 1, $row + 1],
	      w => [-1, -1 - $row, -1 + $row]);
  for my $here (0 .. scalar(@$tiles) - 1) {
  TILE:
    for (@{$tiles->[$here]}) {
      if ($_ eq "pillar") {
	# $log->debug("$here: $_");
	# debug_neighbours($tiles, $here);
	for my $dir (qw(n e w s)) {
	  if (something($tiles, $here, $test{$dir}->[0])
	      and not something($tiles, $here, $test{$dir}->[1])
	      and not something($tiles, $here, $test{$dir}->[2])) {
	    # $log->debug("Removing pillar $here");
	    $_ = "empty";
	    next TILE;
	  }
	}
      }
    }
  }
  return $tiles;
}

sub legal {
  # is this position on the map?
  my $here = shift;
  my $delta = shift;
  return if $here + $delta < 0 or $here + $delta > $max;
  return if $here % $row == 0 and $delta == -1;
  return if $here % $row == $row and $delta == 1;
  return 1;
}

sub something {
  # Is there something at this legal position? Off the map means there is
  # nothing at the position.
  my $tiles = shift;
  my $here = shift;
  my $delta = shift;
  return if not legal($here, $delta);
  return @{$tiles->[$here + $delta]} if $tiles->[$here + $delta];
}

sub empty {
  # Is this position legal and empty? We're looking for the "empty" tile!
  my $tiles = shift;
  my $here = shift;
  my $delta = shift;
  return if not legal($here, $delta);
  return grep { $_ eq "empty" } @{$tiles->[$here + $delta]};
}

sub debug_neighbours {
  my $tiles = shift;
  my $here = shift;
  my @n;
  if ($here > $row and $tiles->[$here - $row] and @{$tiles->[$here - $row]}) {
    push(@n, "n: @{$tiles->[$here - $row]}");
  }
  if ($here + $row <= $max and $tiles->[$here + $row] and @{$tiles->[$here + $row]}) {
    push(@n, "s: @{$tiles->[$here + $row]}");
  }
  if ($here > 0 and $tiles->[$here - 1] and @{$tiles->[$here - 1]}) {
    push(@n, "w: @{$tiles->[$here - 1]}");
  }
  if ($here < $max and $tiles->[$here + 1] and @{$tiles->[$here + 1]}) {
    push(@n, "e: @{$tiles->[$here + 1]}");
  }
  $log->debug("Neighbours of $here: @n");
  for (-$row-1, -$row, -$row+1, -1, +1, $row-1, $row, $row+1) {
    eval { $log->debug("Neighbours of $here+$_: @{$tiles->[$here + $_]}") };
  }
}

sub to_text {
  # Don't forget the border of two tiles.
  my $tiles = shift;
  my $text = "include $contrib/gridmapper.txt\n";
  for my $x (0 .. $row - 1) {
    for my $y (0 .. $col - 1) {
      my $tile = $tiles->[$x + $y * $row];
      if ($tile) {
	$text .= sprintf("%02d%02d @$tile\n", $x + 1, $y + 1);
      }
    }
  }
  return $text;
}

1;
