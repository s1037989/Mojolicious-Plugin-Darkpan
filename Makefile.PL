use strict;
use warnings;

use ExtUtils::MakeMaker;

WriteMakefile(
  NAME         => 'Mojolicious::Plugin::Darkpan',
  VERSION_FROM => 'lib/Mojolicious/Plugin/Darkpan.pm',
  AUTHOR       => 'Stefan Adams <sadams@cpan.org>',
  LICENSE      => 'artistic_2',
  META_MERGE   => {
    dynamic_config => 0,
    'meta-spec'    => {version => 2},
    no_index       =>
      {directory => [qw(t)], package => [qw(Mojo::File::Role::MakePath)],},
    prereqs   => {runtime => {requires => {perl => '5.016'}}},
    resources => {
      bugtracker => {web => 'https://github.com/stefanadams/mojolicious-plugin-darkpan/issues'},
      homepage   => 'https://stefan.adams.fm',
      license    => ['http://www.opensource.org/licenses/artistic-license-2.0'],
      repository => {
        type => 'git',
        url  => 'https://github.com/stefanadams/mojolicious-plugin-darkpan.git',
        web  => 'https://github.com/stefanadams/mojolicious-plugin-darkpan',
      },
      x_IRC => {url => 'irc://irc.libera.chat/#mojo', web => 'https://web.libera.chat/#mojo'}
    },
  },
  PREREQ_PM    => {
    'Archive::Tar'          => '2.38',
    'File::MimeInfo::Magic' => '0.33',
    'Mojolicious'           => '9.29',
  },
  EXE_FILES    => ['script/darkpan'],
  test         => {TESTS => 't/*.t'}
);
