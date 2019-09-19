#!/usr/bin/env perl

use Modern::Perl;
use Path::Tiny;

my $pkg;
my $text;
open my $pbpaste, '-|', 'pbpaste' or die $!;
$text=do { local $/; <$pbpaste> };
close $pbpaste;

if ($text =~ m{^package\s+(\S+);}) {
  $pkg=$1;
}
else {
  die "no package statement found";
}

my $file=$pkg;
$file =~ s{::}{/}g;
$file .= '.pm';
$file=path $file;

unless (-d $file->parent) {
  $file->parent->mkpath;
}

$file->spew($text, "\n1;\n");

system 'ls', '-ld', $file;

