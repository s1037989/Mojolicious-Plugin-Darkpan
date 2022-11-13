use strict;
use warnings;

use ExtUtils::MakeMaker;

WriteMakefile(
  NAME         => 'Mojolicious::Plugin::Darkpan',
  VERSION_FROM => 'lib/Mojolicious/Plugin/Darkpan.pm',
  AUTHOR       => 'Stefan Adams <sadams@cpan.org>',
  PREREQ_PM    => {'Mojolicious' => '9.29'},
  test         => {TESTS => 't/*.t'}
);
