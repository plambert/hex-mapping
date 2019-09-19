package Mojolicious::Command::random;
use Mojo::Base 'Mojolicious::Command';
use Smale;

has description => 'Print a random map to STDOUT';

has usage => <<EOF;
Usage example:
perl text-mapper.pl random > map.txt

This prints a random map description to STDOUT.

You can also pipe this:

perl text-mapper.pl random | perl text-mapper.pl render > map.svg

EOF

sub run {
  my ($self, @args) = @_;
  print Smale::generate_map();
}

1;
