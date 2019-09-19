package Mojolicious::Command::render;
use Mojo::Base 'Mojolicious::Command';
use Mapper::Hex;

has description => 'Render map from STDIN';

has usage => <<EOF;
Usage example:
perl text-mapper.pl render < contrib/forgotten-depths.txt > forgotten-depths.svg

This reads a map description from STDIN and prints the resulting SVG map to
STDOUT.
EOF

sub run {
  my ($self, @args) = @_;
  local $/ = undef;
  my $map = new Mapper::Hex;
  $map->initialize(<STDIN>);
  print $map->svg;
}

1;
