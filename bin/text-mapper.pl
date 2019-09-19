#!/usr/bin/env perl
# Copyright (C) 2009-2019  Alex Schroeder <alex@gnu.org>
#
# This program is free software: you can redistribute it and/or modify it under
# the terms of the GNU General Public License as published by the Free Software
# Foundation, either version 3 of the License, or (at your option) any later
# version.
#
# This program is distributed in the hope that it will be useful, but WITHOUT
# ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
# FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License along with
# this program. If not, see <http://www.gnu.org/licenses/>.

package main;
use Modern::Perl;
use Mojolicious::Lite;
use Mojo::DOM;
use Mojo::Util qw(xml_escape);
use Pod::Simple::HTML;
use Pod::Simple::Text;
use FindBin;
use lib "${FindBin::Bin}/../lib";
use Mapper;
use Mapper::Square;
use Mapper::Hex;
use Smale;
use Schroeder;
use Schroeder::Hex;
use Schroeder::Square;

my $dx = 100;
my $dy = 100*sqrt(3);
my $debug;
our $log;
our $contrib;

sub url_encode {
  my $str = shift;
  return '' unless $str;
  utf8::encode($str); # turn to byte string
  my @letters = split(//, $str);
  my %safe = map {$_ => 1} ('a' .. 'z', 'A' .. 'Z', '0' .. '9', '-', '_', '.', '!', '~', '*', "'", '(', ')', '#');
  foreach my $letter (@letters) {
    $letter = sprintf("%%%02x", ord($letter)) unless $safe{$letter};
  }
  return join('', @letters);
}

plugin Config => {default => {
  loglevel => 'warn',
  contrib => 'https://campaignwiki.org/contrib', }};

$log = Mojo::Log->new;
$log->level(app->config('loglevel'));
$debug = $log->level eq 'debug';
$contrib = app->config('contrib');

get '/' => sub {
  my $c = shift;
  my $param = $c->param('map');
  if ($param) {
    my $map;
    if ($c->param('type') and $c->param('type') eq 'square') {
      $map = new Mapper::Square;
    } else {
      $map = new Mapper::Hex;
    }
    $map->initialize($param);
    $c->render(text => $map->svg, format => 'svg');
  } else {
    $c->render(template => 'edit', map => Mapper::example());
  }
};

any '/edit' => sub {
  my $c = shift;
  my $map = $c->param('map') || Mapper::example();
  $c->render(map => $map);
};

any '/render' => sub {
  my $c = shift;
  my $map;
  if ($c->param('type') and $c->param('type') eq 'square') {
    $map = new Mapper::Square;
  } else {
    $map = new Mapper::Hex;
  }
  $map->initialize($c->param('map'));
  $c->render(text => $map->svg, format => 'svg');
};

get '/:type/redirect' => sub {
  my $self = shift;
  my $type = $self->param('type');
  $self->redirect_to($self->url_for($type . "random")->query(seed => time));
} => 'redirect';

# alias for /smale
get '/random' => sub {
  my $c = shift;
  my $bw = $c->param('bw');
  my $width = $c->param('width');
  my $height = $c->param('height');
  $c->render(template => 'edit', map => Smale::generate_map($bw, $width, $height));
};

get '/smale' => sub {
  my $c = shift;
  my $bw = $c->param('bw');
  my $width = $c->param('width');
  my $height = $c->param('height');
  if ($c->stash('format')||'' eq 'txt') {
    $c->render(text => Smale::generate_map(undef, $width, $height));
  } else {
    $c->render(template => 'edit',
	       map => Smale::generate_map($bw, $width, $height));
  }
};

get '/smale/random' => sub {
  my $c = shift;
  my $bw = $c->param('bw');
  my $width = $c->param('width');
  my $height = $c->param('height');
  my $svg = Mapper::Hex->new()
      ->initialize(Smale::generate_map($bw, $width, $height))
      ->svg();
  $c->render(text => $svg, format => 'svg');
};

get '/smale/random/text' => sub {
  my $c = shift;
  my $bw = $c->param('bw');
  my $width = $c->param('width');
  my $height = $c->param('height');
  my $text = Smale::generate_map($bw, $width, $height);
  $c->render(text => $text, format => 'txt');
};

sub alpine_map {
  my $c = shift;
  # must be able to override this for the documentation
  my $step = shift // $c->param('step');
  # need to compute the seed here so that we can send along the URL
  my $seed = $c->param('seed') || int(rand(1000000000));
  my $url = $c->url_with('alpinedocument')->query({seed => $seed})->to_abs;
  my @params = ($c->param('width'),
		$c->param('height'),
		$c->param('steepness'),
		$c->param('peaks'),
		$c->param('peak'),
		$c->param('bumps'),
		$c->param('bump'),
		$c->param('bottom'),
		$c->param('arid'),
		$seed,
		$url,
		$step,
      );
  my $type = $c->param('type') // 'hex';
  if ($type eq 'hex') {
    return Schroeder::Hex->new()->generate_map(@params);
  } else {
    return Schroeder::Square->new()->generate_map(@params);
  }
}

get '/alpine' => sub {
  my $c = shift;
  my $map = alpine_map($c);
  if ($c->stash('format') || '' eq 'txt') {
    $c->render(text => $map);
  } else {
    $c->render(template => 'edit', map => $map);
  }
};

get '/alpine/random' => sub {
  my $c = shift;
  my $map = alpine_map($c);
  my $type = $c->param('type') // 'hex';
  my $mapper;
  if ($type eq 'hex') {
    $mapper = Mapper::Hex->new();
  } else {
    $mapper = Mapper::Square->new();
  }
  my $svg = $mapper->initialize($map)->svg;
  $c->render(text => $svg, format => 'svg');
};

get '/alpine/random/text' => sub {
  my $c = shift;
  my $map = alpine_map($c);
  $c->render(text => $map, format => 'txt');
};

get '/alpine/document' => sub {
  my $c = shift;
  # prepare a map for every step
  my @maps;
  my $type = $c->param('type') || 'hex';
  # use the same seed for all the calls
  my $seed = $c->param('seed');
  $seed = $c->param('seed' => int(rand(1000000000))) unless defined $seed;
  for my $step (1 .. 15) {
    my $map = alpine_map($c, $step);
    my $mapper;
    if ($type eq 'hex') {
      $mapper = Mapper::Hex->new();
    } else {
      $mapper = Mapper::Square->new();
    }
    my $svg = $mapper->initialize($map)->svg;
    $svg =~ s/<\?xml version="1.0" encoding="UTF-8" standalone="no"\?>\n//g;
    push(@maps, $svg);
  };
  $c->stash("maps" => \@maps);

  # the documentation needs all the defaults of Schroeder::generate_map (but
  # we'd like to use a smaller map because it is so slow)
  my $width = $c->param('width') // 20;
  my $height = $c->param('height') // 5; # instead of 10
  my $steepness = $c->param('steepness') // 3;
  my $peaks = $c->param('peaks') // int($width * $height / 40);
  my $peak = $c->param('peak') // 10;
  my $bumps = $c->param('bumps') // int($width * $height / 40);
  my $bump = $c->param('bump') // 2;
  my $bottom = $c->param('bottom') // 0;
  my $arid = $c->param('arid') // 2;

  $c->render(template => 'alpine_document',
	     seed => $seed,
	     width => $width,
	     height => $height,
	     steepness => $steepness,
	     peaks => $peaks,
	     peak => $peak,
	     bumps => $bumps,
	     bump => $bump,
	     bottom => $bottom,
	     arid => $arid);
};

get '/alpine/parameters' => sub {
  my $c = shift;
  $c->render(template => 'alpine_parameters');
};

sub gridmapper_map {
  my $c = shift;
  my $seed = $c->param('seed') || int(rand(1000000000));
  my $pillars = $c->param('pillars') // 1;
  srand($seed);
  return Gridmapper->new()->generate_map($pillars);
}

get '/gridmapper' => sub {
  my $c = shift;
  my $map = gridmapper_map($c);
  if ($c->stash('format') || '' eq 'txt') {
    $c->render(text => $map);
  } else {
    $c->render(template => 'edit', map => $map);
  }
};

get '/gridmapper/random' => sub {
  my $c = shift;
  my $map = gridmapper_map($c);
  my $mapper = Mapper::Square->new();
  my $svg = $mapper->initialize($map)->svg;
  $c->render(text => $svg, format => 'svg');
};

get '/gridmapper/random/text' => sub {
  my $c = shift;
  my $map = gridmapper_map($c);
  $c->render(text => $map, format => 'txt');
};

get '/source' => sub {
  my $c = shift;
  seek(DATA,0,0);
  local $/ = undef;
  $c->render(text => <DATA>, format => 'txt');
};

get '/help' => sub {
  my $c = shift;

  seek(DATA,0,0);
  local $/ = undef;
  my $pod = <DATA>;
  $pod =~ s/\$contrib/$contrib/g;
  my $parser = Pod::Simple::HTML->new;
  $parser->html_header_after_title('');
  $parser->html_header_before_title('');
  $parser->title_prefix('<!--');
  $parser->title_postfix('-->');
  my $html;
  $parser->output_string(\$html);
  $parser->parse_string_document($pod);

  my $dom = Mojo::DOM->new($html);
  for my $pre ($dom->find('pre')->each) {
    my $map = $pre->text;
    $map =~ s/^    //mg;
    next if $map =~ /^perl/; # how to call it
    my $url = $c->url_for('render')->query(map => $map);
    $pre->replace("<pre>" . xml_escape($map) . "</pre>\n"
		  . qq{<p class="example"><a href="$url">Render this example</a></p>});
  }

  $c->render(html => $dom);
};

app->start;

__DATA__

=encoding utf8

=head1 Text Mapper

The script parses a text description of a hex map and produces SVG output. Use
your browser to view SVG files and use Inkscape to edit them.

Here's a small example:

    grass attributes fill="green"
    0101 grass

We probably want lighter colors.

    grass attributes fill="#90ee90"
    0101 grass

First, we defined the SVG attributes of a hex B<type> and then we
listed the hexes using their coordinates and their type. Adding more
types and extending the map is easy:

    grass attributes fill="#90ee90"
    sea attributes fill="#afeeee"
    0101 grass
    0102 sea
    0201 grass
    0202 sea

You might want to define more SVG attributes such as a border around
each hex:

    grass attributes fill="#90ee90" stroke="black" stroke-width="1px"
    0101 grass

The attributes for the special type B<default> will be used for the
hex layer that is drawn on top of it all. This is where you define the
I<border>.

    default attributes fill="none" stroke="black" stroke-width="1px"
    grass attributes fill="#90ee90"
    sea attributes fill="#afeeee"
    0101 grass
    0102 sea
    0201 grass
    0202 sea

You can define the SVG attributes for the B<text> in coordinates as
well.

    text font-family="monospace" font-size="10pt"
    default attributes fill="none" stroke="black" stroke-width="1px"
    grass attributes fill="#90ee90"
    sea attributes fill="#afeeee"
    0101 grass
    0102 sea
    0201 grass
    0202 sea

You can provide a text B<label> to use for each hex:

    text font-family="monospace" font-size="10pt"
    default attributes fill="none" stroke="black" stroke-width="1px"
    grass attributes fill="#90ee90"
    sea attributes fill="#afeeee"
    0101 grass
    0102 sea
    0201 grass "promised land"
    0202 sea

To improve legibility, the SVG output gives you the ability to define an "outer
glow" for your labels by printing them twice and using the B<glow> attributes
for the one in the back. In addition to that, you can use B<label> to control
the text attributes used for these labels. If you append a number to the label,
it will be used as the new font-size.

    text font-family="monospace" font-size="10pt"
    label font-family="sans-serif" font-size="12pt"
    glow fill="none" stroke="white" stroke-width="3pt"
    default attributes fill="none" stroke="black" stroke-width="1px"
    grass attributes fill="#90ee90"
    sea attributes fill="#afeeee"
    0101 grass
    0102 sea
    0201 grass "promised land"
    0202 sea "deep blue sea" 20

You can define SVG B<path> elements to use for your map. These can be
independent of a type (such as an icon for a settlement) or they can
be part of a type (such as a bit of grass).

Here, we add a bit of grass to the appropriate hex type:

    text font-family="monospace" font-size="10pt"
    label font-family="sans-serif" font-size="12pt"
    glow fill="none" stroke="white" stroke-width="3pt"
    default attributes fill="none" stroke="black" stroke-width="1px"
    grass attributes fill="#90ee90"
    grass path attributes stroke="#458b00" stroke-width="5px"
    grass path M -20,-20 l 10,40 M 0,-20 v 40 M 20,-20 l -10,40
    sea attributes fill="#afeeee"
    0101 grass
    0102 sea
    0201 grass "promised land"
    0202 sea "deep blue sea" 20

Here, we add a settlement. The village doesn't have type attributes (it never
says C<village attributes>) and therefore it's not a hex type.

    text font-family="monospace" font-size="10pt"
    label font-family="sans-serif" font-size="12pt"
    glow fill="none" stroke="white" stroke-width="3pt"
    default attributes fill="none" stroke="black" stroke-width="1px"
    grass attributes fill="#90ee90"
    grass path attributes stroke="#458b00" stroke-width="5px"
    grass path M -20,-20 l 10,40 M 0,-20 v 40 M 20,-20 l -10,40
    village path attributes fill="none" stroke="black" stroke-width="5px"
    village path M -40,-40 v 80 h 80 v -80 z
    sea attributes fill="#afeeee"
    0101 grass
    0102 sea
    0201 grass village "Beachton"
    0202 sea "deep blue sea" 20

As you can see, you can have multiple types per coordinate, but
obviously only one of them should have the "fill" property (or they
must all be somewhat transparent).

As we said above, the village is an independent shape. As such, it also gets the
glow we defined for text. In our example, the glow has a stroke-width of 3pt and
the village path has a stroke-width of 5px which is why we can't see it. If had
used a thinner stroke, we would have seen a white outer glow. Here's the same
example with a 1pt stroke-width for the village.

    text font-family="monospace" font-size="10pt"
    label font-family="sans-serif" font-size="12pt"
    glow fill="none" stroke="white" stroke-width="3pt"
    default attributes fill="none" stroke="black" stroke-width="1px"
    grass attributes fill="#90ee90"
    grass path attributes stroke="#458b00" stroke-width="5px"
    grass path M -20,-20 l 10,40 M 0,-20 v 40 M 20,-20 l -10,40
    village path attributes fill="none" stroke="black" stroke-width="1pt"
    village path M -40,-40 v 80 h 80 v -80 z
    sea attributes fill="#afeeee"
    0101 grass
    0102 sea
    0201 grass village "Beachton"
    0202 sea "deep blue sea" 20

You can also have lines connecting hexes. In order to better control the flow of
these lines, you can provide multiple hexes through which these lines must pass.
You can append a label to these, too. These lines can be used for borders,
rivers or roads, for example.

    text font-family="monospace" font-size="10pt"
    label font-family="sans-serif" font-size="12pt"
    glow fill="none" stroke="white" stroke-width="3pt"
    default attributes fill="none" stroke="black" stroke-width="1px"
    grass attributes fill="#90ee90"
    grass path attributes stroke="#458b00" stroke-width="5px"
    grass path M -20,-20 l 10,40 M 0,-20 v 40 M 20,-20 l -10,40
    village path attributes fill="none" stroke="black" stroke-width="5px"
    village path M -40,-40 v 80 h 80 v -80 z
    sea attributes fill="#afeeee"
    0101 grass
    0102 sea
    0201 grass village "Beachton"
    0202 sea "deep blue sea" 20
    border path attributes stroke="red" stroke-width="15" stroke-opacity="0.5" fill-opacity="0"
    0002-0200 border "The Wall"
    road path attributes stroke="black" stroke-width="3" fill-opacity="0" stroke-dasharray="10 10"
    0000-0301 road

=head3 Include a Library

Since these definitions get unwieldy, require a lot of work (the path
elements), and to encourage reuse, you can use the B<include>
statement with an URL.

    include $contrib/default.txt
    0102 sand
    0103 sand
    0201 sand
    0202 jungle "oasis"
    0203 sand
    0302 sand
    0303 sand

You can find more files ("libraries") to include in the C<contrib>
directory:
L<https://alexschroeder.ch/cgit/hex-mapping/tree/contrib>.

=head3 Large Areas

If you want to surround a piece of land with a round shore line, a
forest with a large green shadow, you can achieve this using a line
that connects to itself. These "closed" lines can have C<fill> in
their path attributes. In the following example, the oasis is
surrounded by a larger green area.

    include $contrib/default.txt
    0102 sand
    0103 sand
    0201 sand
    0203 sand
    0302 sand
    0303 sand
    0102-0201-0302-0303-0203-0103-0102 green
    green path attributes fill="#9acd32"
    0202 jungle "oasis"

Confusingly, the "jungle path attributes" are used to draw the palm
tree, so we cannot use it do define the area around the oasis. We need
to define the green path attributes in order to do that.

I<Order is important>: First we draw the sand, then the green area,
then we drop a jungle on top of the green area.

=head2 Random

There's a button to generate a random landscape based on the algorithm
developed by Erin D. Smale. See
L<http://www.welshpiper.com/hex-based-campaign-design-part-1/> and
L<http://www.welshpiper.com/hex-based-campaign-design-part-2/> for
more information. The output uses the I<Gnomeyland> icons by Gregory
B. MacKenzie. These are licensed under the Creative Commons
Attribution-ShareAlike 3.0 Unported License. To view a copy of this
license, visit L<http://creativecommons.org/licenses/by-sa/3.0/>.

If you're curious: (11,11) is the starting hex.

=head2 SVG

You can define shapes using arbitrary SVG. Your SVG will end up in the
B<defs> section of the SVG output. You can then refer to the B<id>
attribute in your map definition. For the moment, all your SVG needs to
fit on a single line.

    <circle id="thorp" fill="#ffd700" stroke="black" stroke-width="7" cx="0" cy="0" r="15"/>
    0101 thorp

Shapes can include each other:

    <circle id="settlement" fill="#ffd700" stroke="black" stroke-width="7" cx="0" cy="0" r="15"/>
    <path id="house" stroke="black" stroke-width="7" d="M-15,0 v-50 m-15,0 h60 m-15,0 v50 M0,0 v-37"/>
    <use id="thorp" xlink:href="#settlement" transform="scale(0.6)"/>
    <g id="village" transform="scale(0.6), translate(0,40)"><use xlink:href="#house"/><use xlink:href="#settlement"/></g>
    0101 thorp
    0102 village

When creating new shapes, remember the dimensions of the hex. Your shapes must
be centered around (0,0). The width of the hex is 200px, the height of the hex
is 100 √3 = 173.2px. A good starting point would be to keep it within (-50,-50)
and (50,50).

=head2 Other

You can add even more arbitrary SVG using the B<other> keyword. This
keyword can be used multiple times.

    grass attributes fill="#90ee90"
    0101 grass
    0201 grass
    0302 grass
    other <text x="150" y="20" font-size="40pt" transform="rotate(30)">Tundra of Sorrow</text>

The B<other> keyword causes the item to be added to the end of the
document. It can be used for frames and labels that are not connected
to a single hex.

You can make labels link to web pages using the B<url> keyword.

    grass attributes fill="#90ee90"
    0101 grass "Home"
    url https://campaignwiki.org/wiki/NameOfYourWiki/

This will make the label X link to
C<https://campaignwiki.org/wiki/NameOfYourWiki/X>. You can also use
C<%s> in the URL and then this placeholder will be replaced with the
(URL encoded) label.

=head2 License

This program is copyright (C) 2007-2019 Alex Schroeder <alex@gnu.org>.

This program is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or (at
your option) any later version.

This program is distributed in the hope that it will be useful, but
WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU
General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program. If not, see L<http://www.gnu.org/licenses/>.

The maps produced by the program are obviously copyrighted by I<you>,
the author. If you're using SVG icons, these I<may> have a separate
license. Thus, if you produce a map using the I<Gnomeyland> icons by
Gregory B. MacKenzie, the map is automatically licensed under the
Creative Commons Attribution-ShareAlike 3.0 Unported License. To view
a copy of this license, visit
L<http://creativecommons.org/licenses/by-sa/3.0/>.

You can add arbitrary SVG using the B<license> keyword (without a
tile). This is what the Gnomeyland library does, for example.

    grass attributes fill="#90ee90"
    0101 grass
    license <text>Public Domain</text>

There can only be I<one> license keyword. If you use multiple
libraries or want to add your own name, you will have to write your
own.

There's a 50 pixel margin around the map, here's how you might
conceivably use it for your own map that uses the I<Gnomeyland> icons
by Gregory B. MacKenzie:

    grass attributes fill="#90ee90"
    0101 grass
    0201 grass
    0301 grass
    0401 grass
    0501 grass
    license <text x="50" y="-33" font-size="15pt" fill="#999999">Copyright Alex Schroeder 2013. <a style="fill:#8888ff" xlink:href="http://www.busygamemaster.com/art02.html">Gnomeyland Map Icons</a> Copyright Gregory B. MacKenzie 2012.</text><text x="50" y="-15" font-size="15pt" fill="#999999">This work is licensed under the <a style="fill:#8888ff" xlink:href="http://creativecommons.org/licenses/by-sa/3.0/">Creative Commons Attribution-ShareAlike 3.0 Unported License</a>.</text>

Unfortunately, it all has to go on a single line.

=head2 Examples

=head3 Default

Source of the map:
L<http://themetalearth.blogspot.ch/2011/03/opd-entry.html>

Example data:
L<$contrib/forgotten-depths.txt>

Library:
L<$contrib/default.txt>

Result:
L<https://campaignwiki.org/text-mapper?map=include+$contrib/forgotten-depths.txt>

=head3 Gnomeyland

Example data:
L<$contrib/gnomeyland-example.txt>

Library:
L<$contrib/gnomeyland.txt>

Result:
L<https://campaignwiki.org/text-mapper?map=include+$contrib/gnomeyland-example.txt>

=head3 Traveller

Example:
L<$contrib/traveller-example.txt>

Library:
L<$contrib/traveller.txt>

Result:
L<https://campaignwiki.org/text-mapper?map=include+$contrib/traveller-example.txt>

=head3 Dungeons

Example:
L<$contrib/gridmapper-example.txt>

Library:
L<$contrib/gridmapper.txt>

Result:
L<https://campaignwiki.org/text-mapper?type=square&map=include+$contrib/gridmapper-example.txt>

=head2 Configuration

As a Mojolicious application, it will read a config file called
F<text-mapper.conf> in the same directory, if it exists. As the default log
level is 'warn', one use of the config file is to change the log level using
the C<loglevel> key.

The libraries are loaded from the F<contrib> URL. You can change the default
using the C<contrib> key. This is necessary when you want to develop locally,
for example.

    {
      loglevel => 'debug',
      contrib => 'file://contrib',
    };

=head2 Command Line

You can call the script from the command line. The B<render> command reads a map
description from STDIN and prints it to STDOUT.

    perl text-mapper.pl render < contrib/forgotten-depths.txt > forgotten-depths.svg

The B<random> command prints a random map description to STDOUT.

    perl text-mapper.pl random > map.txt

Thus, you can pipe the random map in order to render it:

    perl text-mapper.pl random | perl text-mapper.pl render > map.svg

You can read this documentation in a text terminal, too:

    pod2text text-mapper.pl

Alternatively:

    perl text-mapper.pl get /help | w3m -T text/html

=cut


@@ help.html.ep
% layout 'default';
% title 'Text Mapper: Help';
<%== $html %>


@@ edit.html.ep
% layout 'default';
% title 'Text Mapper';
<h1>Text Mapper</h1>
<p>Submit your text desciption of the map.</p>
%= form_for render => (method => 'POST') => begin
%= text_area map => (cols => 60, rows => 15) => begin
<%= $map =%>
% end

<p>
%= radio_button type => 'hex', id => 'hex', checked => undef
%= label_for hex => 'Hex'
%= radio_button type => 'square', id => 'square'
%= label_for square => 'Square'

<p>
%= submit_button
</p>
%= end

<p>
<%= link_to smale => begin %>Random<% end %>
will generate map data based on Erin D. Smale's <em>Hex-Based Campaign Design</em>
(<a href="http://www.welshpiper.com/hex-based-campaign-design-part-1/">Part 1</a>,
<a href="http://www.welshpiper.com/hex-based-campaign-design-part-2/">Part 2</a>).
You can also generate a random map
<%= link_to url_for('smale')->query(bw => 1) => begin %>with no background colors<% end %>.
Click the submit button to generate the map itself. Or just keep reloading
<%= link_to smalerandom => begin %>this link<% end %>.
You'll find the map description in a comment within the SVG file.
</p>
%= form_for smale => begin
<table>
<tr><td>Width:</td><td>
%= number_field width => 20, min => 5, max => 99
</td></tr><tr><td>Height:</td><td>
%= number_field height => 10, min => 5, max => 99
</td></tr></table>
%= submit_button
% end
<p>
<%= link_to alpine => begin %>Alpine<% end %> will generate map data based on Alex
Schroeder's algorithm that's trying to recreate a medieval Swiss landscape, with
no info to back it up, whatsoever. See it
<%= link_to url_for('alpinedocument')->query(height => 5) => begin %>documented<% end %>.
Click the submit button to generate the map itself. Or just keep reloading
<%= link_to alpinerandom => begin %>this link<% end %>.
You'll find the map description in a comment within the SVG file.
</p>
%= form_for alpine => begin
<table>
<tr><td>Width:</td><td>
%= number_field width => 20, min => 5, max => 99
</td><td>Bottom:</td><td>
%= number_field bottom => 0, min => 0, max => 10
</td><td>Peaks:</td><td>
%= number_field peaks => 5, min => 0, max => 100
</td><td>Bumps:</td><td>
%= number_field bumps => 2, min => 0, max => 100
</td></tr><tr><td>Height:</td><td>
%= number_field height => 10, min => 5, max => 99
</td><td>Steepness:</td><td>
%= number_field steepness => 3, min => 1, max => 6
</td><td>Peak:</td><td>
%= number_field peak => 10, min => 7, max => 10
</td><td>Bump:</td><td>
%= number_field bump => 2, min => 1, max => 2
</td></tr><tr><td>Arid:</td><td>
%= number_field arid => 2, min => 0, max => 2
</td><td><td>
</td><td></td><td>
</td></tr></table>
<p>
See the <%= link_to alpineparameters => begin %>documentation<% end %> for an
explanation of what these parameters do.
<p>
%= radio_button type => 'hex', id => 'hex', checked => undef
%= label_for hex => 'Hex'
%= radio_button type => 'square', id => 'square'
%= label_for square => 'Square'
</p>
%= submit_button
% end
<p>
<%= link_to url_for('gridmapper')->query(type => 'square') => begin%>Gridmapper<% end %>
will generate dungeon map data based on geomorph sketches by Robin Green. Or
just keep reloading <%= link_to gridmapperrandom => begin %>this link<% end %>.
%= form_for gridmapper => begin
<p>
<label>
%= check_box pillars => 0
No rooms with pillars
</label>
%= hidden_field type => 'square'
<p>
%= submit_button
% end

@@ render.svg.ep


@@ alpine_parameters.html.ep
% layout 'default';
% title 'Alpine Parameters';
<h1>Alpine Parameters</h1>

<p>
This page explains what the parameters for the <em>Alpine</em> map generation
will do.
</p>
<p>
The parameters <strong>width</strong> and <strong>height</strong> determine how
big the map is.
</p>
<p>
Example:
<%= link_to url_for('alpinerandom')->query(height => 10, width => 15) => begin %>15×10 map<% end %>.
</p>
<p>
The number of peaks we start with is controlled by the <strong>peaks</strong>
parameter (default is 2½% of the hexes). Note that you need at least one peak in
order to get any land at all.
</p>
<p>
Examples:
<%= link_to url_for('alpinerandom')->query(height => 10, width => 15, peaks => 1) => begin %>lonely mountain<% end %>,
<%= link_to url_for('alpinerandom')->query(height => 10, width => 15, peaks => 2) => begin %>twin peaks<% end %>,
<%= link_to url_for('alpinerandom')->query(height => 10, width => 15, peaks => 15) => begin %>here be glaciers<% end %>
</p>
<p>
The number of bumps we start with is controlled by the <strong>bumps</strong>
parameter (default is 1% of the hexes). These are secondary hills and hollows.
</p>
<p>
Examples:
<%= link_to url_for('alpinerandom')->query(height => 10, width => 15, peaks => 1, bumps => 0) => begin %>lonely mountain, no bumps<% end %>,
<%= link_to url_for('alpinerandom')->query(height => 10, width => 15, peaks => 1, bumps => 4) => begin %>lonely mountain and four bumps<% end %>
</p>
<p>
When creating elevations, we surround each hex with a number of other hexes at
one altitude level lower. The number of these surrounding lower levels is
controlled by the <strong>steepness</strong> parameter (default 3). Lower means
steeper. Floating points are allowed. Please note that the maximum numbers of
neighbors considered is the 6 immediate neighbors and the 12 neighbors one step
away.
</p>
<p>
Examples:
<%= link_to url_for('alpinerandom')->query(height => 10, width => 15, steepness => 0) => begin %>ice needles map<% end %>,
<%= link_to url_for('alpinerandom')->query(height => 10, width => 15, steepness => 2) => begin %>steep mountains map<% end %>,
<%= link_to url_for('alpinerandom')->query(height => 10, width => 15, steepness => 4) => begin %>big mountains map<% end %>
</p>
<p>
The sea level is set to altitude 0. That's how you sometimes get a water hex at
the edge of the map. You can simulate global warming and set it to something
higher using the <strong>bottom</strong> parameter.
</p>
<p>
Example:
<%= link_to url_for('alpinerandom')->query(height => 10, width => 15, steepness => 2, bottom => 5) => begin %>steep mountains and higher water level map<% end %>
</p>
<p>
You can also control how high the highest peaks will be using the
<strong>peak</strong> parameter (default 10). Note that nothing special happens
to a hex with an altitude above 10. It's still mountain peaks. Thus, setting the
parameter to something higher than 10 just makes sure that there will be a lot
of mountain peaks.
</p>
<p>
Examples:
<%= link_to url_for('alpinerandom')->query(height => 10, width => 15, peak => 11) => begin %>big mountains<% end %>,
<%= link_to url_for('alpinerandom')->query(height => 10, width => 15, steepness => 3, bottom => 3, peak => 8) => begin %>old country<% end %>
</p>
<p>
You can also control how high the extra bumps will be using the
<strong>bump</strong> parameter (default 2).
</p>
<p>
Examples:
<%= link_to url_for('alpinerandom')->query(height => 10, width => 15, peaks => 1, bump => 1) => begin %>small bumps<% end %>,
<%= link_to url_for('alpinerandom')->query(height => 10, width => 15, peaks => 1, bump => 2) => begin %>bigger bumps<% end %>
</p>
<p>
You can also control forest growth (as opposed to grassland) by using the
<strong>arid</strong> parameter (default 2). That's how many hexes surrounding a
river hex will grow forests. Smaller means more arid and thus more grass.
Fractions are allowed. Thus, 0.5 means half the river hexes will have forests
grow to their neighbouring hexes.
</p>
<p>
Examples:
<%= link_to url_for('alpinerandom')->query(height => 10, width => 15, peaks => 2, stepness => 2, arid => 2) => begin %>fewer, steeper mountains<% end %>,
<%= link_to url_for('alpinerandom')->query(height => 10, width => 15, peaks => 2, stepness => 2, arid => 1) => begin %>less forest<% end %>,
<%= link_to url_for('alpinerandom')->query(height => 10, width => 15, peaks => 2, stepness => 2, arid => 0) => begin %>very arid<% end %>
</p>


@@ alpine_document.html.ep
% layout 'default';
% title 'Alpine Documentation';
<h1>Alpine Map: How does it get created?</h1>

<p>How do we get to the following map?
<%= link_to url_for('alpinedocument')->query(width => $width, height => $height, steepness => $steepness, peaks => $peaks, peak => $peak, bumps => $bumps, bump => $bump, bottom => $bottom, arid => $arid) => begin %>Reload<% end %>
to get a different one. If you like this particular map, bookmark
<%= link_to url_for('alpinerandom')->query(seed => $seed, width => $width, height => $height, steepness => $steepness, peaks => $peaks, peak => $peak, bumps => $bumps, bump => $bump, bottom => $bottom, arid => $arid) => begin %>this link<% end %>,
and edit it using
<%= link_to url_for('alpine')->query(seed => $seed, width => $width, height => $height, steepness => $steepness, peaks => $peaks, peak => $peak, bumps => $bumps, bump => $bump, bottom => $bottom, arid => $arid) => begin %>this link<% end %>,
</p>

%== $maps->[$#$maps]

<p>First, we pick <%= $peaks %> peaks and set their altitude to <%= $peak %>.
Then we loop down to 1 and for every hex we added in the previous run, we add
<%= $steepness %> neighbors at a lower altitude, if possible. We actually vary
steepness, so the steepness given is just an average. We'll also consider
neighbors one step away. If our random growth missed any hexes, we just copy the
height of a neighbor. If we can't find a suitable neighbor within a few tries,
just make a hole in the ground (altitude 0).</p>

<p>The number of peaks can be changed using the <em>peaks</em> parameter. Please
note that 0 <em>peaks</em> will result in no land mass.</p>

<p>The initial altitude of those peaks can be changed using the <em>peak</em>
parameter. Please note that a <em>peak</em> smaller than 7 will result in no
sources for rivers.</p>

<p>The number of adjacent hexes at a lower altitude can be changed using the
<em>steepness</em> parameter. Floating points are allowed. Please note that the
maximum numbers of neighbors considered is the 6 immediate neighbors and the 12
neighbors one step away.</p>

%== shift(@$maps)

<p>Next, we pick <%= $bumps %> bumps and shift their altitude by -<%= $bump %>,
and <%= $bumps %> bumps and shift their altitude by +<%= $bump %>. If the shift
is bigger than 1, then we shift the neighbours by one less.</p>

%== shift(@$maps)

<p>Mountains are the hexes at high altitudes: white mountains (altitude 10),
white mountain (altitude 9), light-grey mountain (altitude 8).</p>

%== shift(@$maps)

<p>We determine the flow of water by having water flow to one of the lowest
neighbors if possible. Water doesn't flow upward, and if there is already water
coming our way, then it won't flow back. It has reached a dead end.</p>

%== shift(@$maps)

<p>Any of the dead ends we found in the previous step are marked as lakes.
Anthing beneath an altitude of <%= $bottom %> is marked the same. This is
considered to be the sea level.</p>

%== shift(@$maps)

<p>We still need to figure out how to drain lakes. In order to do that, we start
"flooding" lakes, looking for a way to the edge of the map. If we're lucky, our
search will soon hit upon a sequence of arrows that leads to ever lower
altitudes and to the edge of the map. An outlet! We start with all the hexes
that don't have an arrow. For each one of those, we look at its neighbors. These
are our initial candidates. We keep expanding our list of candidates as we add
at neighbors of neighbors. At every step we prefer the lowest of these
candidates. Once we have reached the edge of the map, we backtrack and change
any arrows pointing the wrong way.</p>

%== shift(@$maps)

<p>We add bogs (altitude 7) if the water flows into a hex at the same altitude.
It is insufficiently drained. We use grey swamps to indicate this.</p>

%== shift(@$maps)

<p>We add a river sources high up in the mountains (altitudes 7 and 8), merging
them as appropriate. These rivers flow as indicated by the arrows. If the river
source is not a mountain (altitude 8) or a bog (altitude 7), then we place a
forested hill at the source (thus, they're all at altitude 7).</p>

%== shift(@$maps)

<p>Remember how the arrows were changed at some points such that rivers don't
always flow downwards. We're going to assume that in these situations, the
rivers have cut canyons into the higher lying ground and we'll add a little
shadow.</p>

%== shift(@$maps)

<p>Any hex <em>with a river</em> that flows towards a neighbor at the same
altitude is insufficiently drained. These are marked as swamps. The background
color of the swamp depends on the altitude: grey if altitude 6 and higher,
otherwise dark-grey.</p>

%== shift(@$maps)

<p>Wherever there is water and no swamp, forests will form. The exact type again
depends on the altitude: light green fir-forest (altitude 7 and higher), green
fir-forest (altitude 6), green forest (altitude 4–5), dark-green forest
(altitude 3 and lower). Once a forest is placed, it expands up to <%= $arid %> hexes
away, even if those hexes have no water flowing through them. You probably need
fewer peaks on your map to verify this (a <%= link_to
url_with('alpinerandom')->query({peaks => 1}) => begin %>lonely mountain<% end
%> map, for example).</p>

%== shift(@$maps)

<p>Any remaining hexes have no water nearby and are considered to be little more
arid. They get bushes, a hill (20% of the time at altitudes 3 or higher), or
some grass (60% of the time at altitudes 3 and lower). Higher up, these are
light grey (altitude 6–7), otherwise they are light green (altitude 5 and
below).</p>

%== shift(@$maps)

<p>Cliffs form wherever the drop is more than just one level of altitude.</p>

%== shift(@$maps)

<p>Wherenver there is forest, settlements will be built. These reduce the
density of the forest. There are three levels of settlements: thorps, villages
and towns.</p>

<table>
<tr><th>Settlement</th><th>Forest</th><th>Number</th><th>Minimum Distance</th></tr>
<tr><td>Thorp</td><td>fir-forest, forest</td><td class="numeric">10%</td><td class="numeric">2</td></tr>
<tr><td>Village</td><td>forest &amp; river</td><td class="numeric">5%</td><td class="numeric">5</td></tr>
<tr><td>Town</td><td>forest &amp; river</td><td class="numeric">2½%</td><td class="numeric">10</td></tr>
<tr><td>Law</td><td>white mountain</td><td class="numeric">2½%</td><td class="numeric">10</td></tr>
<tr><td>Chaos</td><td>swamp</td><td class="numeric">2½%</td><td class="numeric">10</td></tr>
</table>

%== shift(@$maps)

<p>Trails connect every settlement to any neighbor that is one or two hexes
away. If no such neighbor can be found, we try to find neighbors that are three
hexes away.</p>

%== shift(@$maps)

@@ layouts/default.html.ep
<!DOCTYPE html>
<html>
<head>
<title><%= title %></title>
%= stylesheet '/text-mapper.css'
%= stylesheet begin
body {
  padding: 1em;
  font-family: "Palatino Linotype", "Book Antiqua", Palatino, serif;
}
textarea {
  width: 100%;
}
table {
  padding-bottom: 1em;
}
td, th {
  padding-right: 0.5em;
}
.example {
  font-size: smaller;
}
.numeric {
  text-align: center;
}
% end
<meta name="viewport" content="width=device-width">
</head>
<body>
<%= content %>
<hr>
<p>
<a href="https://campaignwiki.org/text-mapper">Text Mapper</a>&#x2003;
<%= link_to 'Help' => 'help' %>&#x2003;
<%= link_to 'Source' => 'source' %>&#x2003;
<a href="https://alexschroeder.ch/cgit/hex-mapping/about/#text-mapper">Git</a>&#x2003;
<a href="https://alexschroeder.ch/wiki/Contact">Alex Schroeder</a>
</body>
</html>
