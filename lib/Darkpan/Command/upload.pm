package Darkpan::Command::upload;
use Mojo::Base 'Mojolicious::Command', -signatures;

use Mojo::File qw(path);

has description => 'Upload module to Darkpan';
has usage       => sub { shift->extract_usage };

sub run ($self, @args) {

  $ENV{MOJO_LOG_LEVEL} = 'info';

  die $self->usage =~ s/\$0/$0/r unless my $file = shift @args;
  say $self->app->ua->put('/upload' => path($file)->slurp)->result->body;
}

1;

=encoding utf8

=head1 NAME

Darkpan::Command::upload - Darkpan upload command

=head1 SYNOPSIS

  Usage: APPLICATION upload <file> [OPTIONS]

    $0 upload <file>

  Options:
    -h, --help   Show this summary of available options

=head1 DESCRIPTION

L<Darkpan::Command::upload> uploads a tarball to Darkpan.

This is equivalent to

=over 2

=item * C<curl -T file http://host/upload>

=item * C<mojo get -M PUT /upload E<lt> file>

=back

=head1 ATTRIBUTES

L<Darkpan::Command::upload> inherits all attributes from L<Mojolicious::Command> and implements the following new
ones.

=head2 description

  my $description = $v->description;
  $v              = $v->description('Foo');

Short description of this command, used for the command list.

=head2 usage

  my $usage = $v->usage;
  $v        = $v->usage('Foo');

Usage information for this command, used for the help screen.

=head1 METHODS

L<Darkpan::Command::upload> inherits all methods from L<Mojolicious::Command> and implements the following new
ones.

=head2 run

  $v->run(@ARGV);

Run this command.

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<https://mojolicious.org>.

=cut