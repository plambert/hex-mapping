package Smale;

my %world = ();

#         ATLAS HEX PRIMARY TERRAIN TYPE
#         Water   Swamp   Desert  Plains  Forest  Hills   Mountains
# Water   P       W       W       W       W       W       -
# Swamp   W       P       -       W       W       -       -
# Desert  W       -       P       W       -       W       W
# Plains  S [1]   S       T       P [4]   S       T       -
# Forest  T [2]   T       -       S       P [5]   W [8]   T [11]
# Hills   W       -       S [3]   T       T [6]   P [9]   S
# Mountns -       -       W       -       W [7]   S [10]  P [12]
#
#  1. Treat as coastal (beach or scrub) if adjacent to water
#  2. 66% light forest
#  3. 33% rocky desert or high sand dunes
#  4. Treat as farmland in settled hexes
#  5. 33% heavy forest
#  6. 66% forested hills
#  7. 66% forested mountains
#  8. 33% forested hills
#  9. 20% canyon or fissure (not implemented)
# 10. 40% chance of a pass (not implemented)
# 11. 33% forested mountains
# 12. 20% chance of a dominating peak; 10% chance of a mountain pass (not
#     implemented); 5% volcano (not implemented)
#
# Notes
# water:    water
# sand:     sand or dust
# swamp:    dark-grey swamp (near trees) or dark-grey marshes (no trees)
# plains:   light-green grass, bush or bushes near water or forest
# forest:   green trees (light), green forest, dark-green forest (heavy);
#           use firs and fir-forest near hills or mountains
# hill:     light-grey hill, dust hill if sand dunes
# mountain: grey mountain, grey mountains (peak)

# later, grass land near a settlement might get the colors soil or dark-soil!

my %primary = ("water" =>  ["water"],
	       "swamp" =>  ["dark-grey swamp"],
	       "desert" => ["dust desert"],
	       "plains" => ["light-green grass"],
	       "forest" => ["green forest",
			    "green forest",
			    "dark-green fir-forest"],
	       "hill" =>   ["light-grey hill"],
	       "mountain" => ["grey mountain",
			      "grey mountain",
			      "grey mountain",
			      "grey mountain",
			      "grey mountains"]);

my %secondary = ("water" =>  ["light-green grass",
			      "light-green bush",
			      "light-green bushes"],
		 "swamp" =>  ["light-green grass"],
		 "desert" =>   ["light-grey hill",
				"light-grey hill",
				"dust hill"],
		 "plains" =>  ["green forest"],
		 "forest" => ["light-green grass",
			      "light-green bush"],
		 "hill" =>   ["grey mountain"],
		 "mountain" => ["light-grey hill"]);

my %tertiary = ("water" => ["green forest",
			    "green trees",
			    "green trees"],
		"swamp" => ["green forest"],
		"desert" => ["light-green grass"],
		"plains" => ["light-grey hill"],
		"forest" => ["light-grey forest-hill",
			     "light-grey forest-hill",
			     "light-grey hill"],
		"hill" => ["light-green grass"],
		"mountain" => ["green fir-forest",
			       "green forest",
			       "green forest-mountains"]);

my %wildcard = ("water" => ["dark-grey swamp",
			    "dark-grey marsh",
			    "sand desert",
			    "dust desert",
			    "light-grey hill",
			    "light-grey forest-hill"],
		"swamp" => ["water"],
		"desert" => ["water",
			     "grey mountain"],
		"plains" => ["water",
			     "dark-grey swamp",
			     "dust desert"],
		"forest" => ["water",
			     "water",
			     "water",
			     "dark-grey swamp",
			     "dark-grey swamp",
			     "dark-grey marsh",
			     "grey mountain",
			     "grey forest-mountain",
			     "grey forest-mountains"],
		"hill" => ["water",
			   "water",
			   "water",
			   "sand desert",
			   "sand desert",
			   "dust desert",
			   "green forest",
			   "green forest",
			   "green forest-hill"],
		"mountain" => ["sand desert",
			       "dust desert"]);


my %reverse_lookup = (
  # primary
  "water" => "water",
  "dark-grey swamp" => "swamp",
  "dust desert" => "desert",
  "light-green grass" => "plains",
  "green forest" => "forest",
  "dark-green fir-forest" => "forest",
  "light-grey hill" => "hill",
  "grey mountain" => "mountain",
  "grey mountains" => "mountain",
  # secondary
  "light-green bush" => "plains",
  "light-green bushes" => "plains",
  "dust hill" => "hill",
  # tertiary
  "green trees" => "forest",
  "light-grey forest-hill" => "hill",
  "green fir-forest" => "forest",
  "green forest-mountains" => "forest",
  # wildcard
  "dark-grey marsh" => "swamp",
  "sand desert" => "desert",
  "grey forest-mountain" => "mountain",
  "grey forest-mountains" => "mountain",
  "green forest-hill" => "forest",
  # code
  "light-soil fields" => "plains",
  "soil fields" => "plains",
    );

my %encounters = ("settlement" => ["thorp", "thorp", "thorp", "thorp",
				   "village",
				   "town", "town",
				   "large-town",
				   "city"],
		  "fortress" => ["keep", "tower", "castle"],
		  "religious" => ["shrine", "law", "chaos"],
		  "ruin" => [],
		  "monster" => [],
		  "natural" => []);

my @needs_fields;

sub one {
  my @arr = @_;
  @arr = @{$arr[0]} if @arr == 1 and ref $arr[0] eq 'ARRAY';
  return $arr[int(rand(scalar @arr))];
}

sub member {
  my $element = shift;
  foreach (@_) {
    return 1 if $element eq $_;
  }
}

sub verbose {
  $main::log->info(shift);
}

sub place_major {
  my ($x, $y, $encounter) = @_;
  my $thing = one(@{$encounters{$encounter}});
  return unless $thing;
  verbose("placing $thing ($encounter) at ($x,$y)");
  my $hex = one(full_hexes($x, $y));
  $x += $hex->[0];
  $y += $hex->[1];
  my $coordinates = sprintf("%02d%02d", $x, $y);
  my $primary = $reverse_lookup{$world{$coordinates}};
  my ($color, $terrain) = split(' ', $world{$coordinates}, 2);
  if ($encounter eq 'settlement') {
    if ($primary eq 'plains') {
      $color = one('light-soil', 'soil');
      verbose(" " . $world{$coordinates} . " is $primary and was changed to $color");
    }
    if ($primary ne 'plains' or member($thing, 'large-town', 'city')) {
      push(@needs_fields, [$x, $y]);
    }
  }
  # ignore $terrain for the moment and replace it with $thing
  $world{$coordinates} = "$color $thing";
}

sub populate_region {
  my ($hex, $primary) = @_;
  my $random = rand 100;
  if ($primary eq 'water' and $random < 10
      or $primary eq 'swamp' and $random < 20
      or $primary eq 'sand' and $random < 20
      or $primary eq 'grass' and $random < 60
      or $primary eq 'forest' and $random < 40
      or $primary eq 'hill' and $random < 40
      or $primary eq 'mountain' and $random < 20) {
    place_major($hex->[0], $hex->[1], one(keys %encounters));
  }
}

# Brute forcing by picking random sub hexes until we found an
# unassigned one.

sub pick_unassigned {
  my ($x, $y, @region) = @_;
  my $hex = one(@region);
  my $coordinates = sprintf("%02d%02d", $x + $hex->[0], $y + $hex->[1]);
  while ($world{$coordinates}) {
    $hex = one(@region);
    $coordinates = sprintf("%02d%02d", $x + $hex->[0], $y + $hex->[1]);
  }
  return $coordinates;
}

sub pick_remaining {
  my ($x, $y, @region) = @_;
  my @coordinates = ();
  for my $hex (@region) {
    my $coordinates = sprintf("%02d%02d", $x + $hex->[0], $y + $hex->[1]);
    push(@coordinates, $coordinates) unless $world{$coordinates};
  }
  return @coordinates;
}

# Precomputed for speed

sub full_hexes {
  my ($x, $y) = @_;
  if ($x % 2) {
    return ([0, -2],
	    [-2, -1], [-1, -1], [0, -1], [1, -1], [2, -1],
	    [-2,  0], [-1,  0], [0,  0], [1,  0], [2,  0],
	    [-2,  1], [-1,  1], [0,  1], [1,  1], [2,  1],
	    [-1,  2], [0,  2], [1,  2]);
  } else {
    return ([-1, -2], [0, -2], [1, -2],
	    [-2, -1], [-1, -1], [0, -1], [1, -1], [2, -1],
	    [-2,  0], [-1,  0], [0,  0], [1,  0], [2,  0],
            [-2,  1], [-1,  1], [0,  1], [1,  1], [2,  1],
	    [0,  2]);
  }
}

sub half_hexes {
  my ($x, $y) = @_;
  if ($x % 2) {
    return ([-2, -2], [-1, -2], [1, -2], [2, -2],
	    [-3,  0], [3,  0],
	    [-3,  1], [3,  1],
	    [-2,  2], [2,  2],
	    [-1,  3], [1,  3]);
  } else {
    return ([-1, -3], [1, -3],
	    [-2, -2], [2, -2],
	    [-3, -1], [3, -1],
	    [-3,  0], [3,  0],
	    [-2,  2], [-1,  2], [1,  2], [2,  2]);
  }
}

sub generate_region {
  my ($x, $y, $primary) = @_;
  $world{sprintf("%02d%02d", $x, $y)} = one($primary{$primary});

  my @region = full_hexes($x, $y);
  my $terrain;

  for (1..9) {
    my $coordinates = pick_unassigned($x, $y, @region);
    $terrain = one($primary{$primary});
    verbose(" primary   $coordinates => $terrain");
    $world{$coordinates} = $terrain;
  }

  for (1..6) {
    my $coordinates = pick_unassigned($x, $y, @region);
    $terrain =  one($secondary{$primary});
    verbose(" secondary $coordinates => $terrain");
    $world{$coordinates} = $terrain;
  }

  for my $coordinates (pick_remaining($x, $y, @region)) {
    if (rand > 0.1) {
      $terrain = one($tertiary{$primary});
      verbose(" tertiary  $coordinates => $terrain");
    } else {
      $terrain = one($wildcard{$primary});
      verbose(" wildcard  $coordinates => $terrain");
    }
    $world{$coordinates} = $terrain;
  }

  for my $coordinates (pick_remaining($x, $y, half_hexes($x, $y))) {
    my $random = rand 6;
    if ($random < 3) {
      $terrain = one($primary{$primary});
      verbose("  halfhex primary   $coordinates => $terrain");
    } elsif ($random < 5) {
      $terrain = one($secondary{$primary});
      verbose("  halfhex secondary $coordinates => $terrain");
    } else {
      $terrain = one($tertiary{$primary});
      verbose("  halfhex tertiary  $coordinates => $terrain");
    }
    $world{$coordinates} = $terrain;
  }
}

sub seed_region {
  my ($seeds, $terrain) = @_;
  my $terrain_above;
  for my $hex (@$seeds) {
    verbose("seed_region (" . $hex->[0] . "," . $hex->[1] . ") with $terrain");
    generate_region($hex->[0], $hex->[1], $terrain);
    populate_region($hex, $terrain);
    my $random = rand 12;
    # pick next terrain based on the previous one (to the left); or the one
    # above if in the first column
    my $next;
    $terrain = $terrain_above if $hex->[0] == 1 and $terrain_above;
    if ($random < 6) {
      $next = one($primary{$terrain});
      verbose("picked primary $next");
    } elsif ($random < 9) {
      $next = one($secondary{$terrain});
      verbose("picked secondary $next");
    } elsif ($random < 11) {
      $next = one($tertiary{$terrain});
      verbose("picked tertiary $next");
    } else {
      $next = one($wildcard{$terrain});
      verbose("picked wildcard $next");
    }
    $terrain_above = $terrain if $hex->[0] == 1;
    die "Terrain lacks reverse_lookup: $next\n" unless $reverse_lookup{$next};
    $terrain = $reverse_lookup{$next};
  }
}

sub agriculture {
  for my $hex (@needs_fields) {
    verbose("looking to plant fields near " . sprintf("%02d%02d", $hex->[0], $hex->[1]));
    my $delta = [[[-1,  0], [ 0, -1], [+1,  0], [+1, +1], [ 0, +1], [-1, +1]],  # x is even
		 [[-1, -1], [ 0, -1], [+1, -1], [+1,  0], [ 0, +1], [-1,  0]]]; # x is odd
    my @plains;
    for my $i (0 .. 5) {
      my ($x, $y) = ($hex->[0] + $delta->[$hex->[0] % 2]->[$i]->[0],
		     $hex->[1] + $delta->[$hex->[0] % 2]->[$i]->[1]);
      my $coordinates = sprintf("%02d%02d", $x, $y);
      if ($world{$coordinates}) {
	my ($color, $terrain) = split(' ', $world{$coordinates}, 2);
	verbose("  $coordinates is " . $world{$coordinates} . " ie. " . $reverse_lookup{$world{$coordinates}});
	if ($reverse_lookup{$world{$coordinates}} eq 'plains') {
	  verbose("   $coordinates is a candidate");
	  push(@plains, $coordinates);
	}
      }
    }
    next unless @plains;
    my $target = one(@plains);
    $world{$target} = one('light-soil fields', 'soil fields');
    verbose(" $target planted with " . $world{$target});
  }
}

sub generate_map {
  my ($bw, $width, $height) = @_;
  $width = 20 if not defined $width or $width < 1 or $width > 100;
  $height = 10 if not defined $height or $height < 1 or $height > 100;

  my $seeds;
  for (my $y = 1; $y < $height + 2; $y += 5) {
    for (my $x = 1; $x < $width + 2; $x += 5) {
      # [1,1] [6,3], [11,1], [16,3]
      my $y0 = $y + int(($x % 10) / 3);
      push(@$seeds, [$x, $y0]);
    }
  }

  %world = (); # reinitialize!

  my @seed_terrain = keys %primary;
  seed_region($seeds, one(@seed_terrain));
  agriculture();

  # delete extra hexes we generated to fill the gaps
  for my $coordinates (keys %world) {
    $coordinates =~ /(..)(..)/;
    delete $world{$coordinates} if $1 < 1 or $2 < 1;
    delete $world{$coordinates} if $1 > $width or $2 > $height;
  }

  if ($bw) {
    for my $coordinates (keys %world) {
      my ($color, $rest) = split(' ', $world{$coordinates}, 2);
      if ($rest) {
	$world{$coordinates} = $rest;
      } else {
	delete $world{$coordinates};
      }
    }
  }

  return join("\n", map { $_ . " " . $world{$_} } sort keys %world) . "\n"
    . "include $contrib/gnomeyland.txt\n";
}

1;
