package Mojolicious::Plugin::Darkpan;
use Mojo::Base 'Mojolicious::Plugin', -signatures;

use version;

use Archive::Tar;
use File::MimeInfo::Magic qw(extensions mimetype);
use Mojo::ByteStream qw(b);
use Mojo::Collection qw(c);
use Mojo::File qw(path);
use Mojo::Util qw(camelize gzip);

our $VERSION = '0.01';

has [qw(app config)];
has details => sub ($self) { $self->public->child('modules', '02packages.details.txt') };
has packages => sub ($self) { $self->public->child('authors', 'id') };
has public => sub ($self) { path($self->config->{public} || $self->app->home->child('public'))->with_roles('Mojo::File::Role::MakePath') };

sub history ($self, $module='') { $self->public->child('v1.0', 'history', $module) }

sub register {
  my ($self, $app, $config) = @_;
  $self->app($app)->config($config);

  push @{$app->commands->namespaces}, 'Darkpan::Command';
  my $public = $self->public;
  push @{$app->static->paths}, "$public" unless $self->_grep_static_paths($public);
  my $details = $self->details;
  my $packages = $self->packages;

  $app->hook(after_static => sub ($c) { $c->log->debug($c->req->url->path) });

  $app->helper('reply.json' => sub {
    my $c = shift;
    my $json = {@_>1?@_:%{shift()}, map { $c->param($_) ? ($_ => $c->param($_)) : () } qw(module version package)};
    $c->render(json => $json);
    return $json;
  });
  $app->helper('hash.file' => sub ($c, $m, $p) {
    ((map { substr(uc(camelize($m)), 0, $_)||'' } (1..3)), lc($p));
  });
  $app->helper('check_upload' => sub ($c) {
    my $ext = ((extensions(mimetype($c->req->content->asset->to_file->path)))[0]);
    $ext = "tar.$ext" unless $ext eq 'tar';
    my $package = $c->param('package') ||
      ((Archive::Tar->new->read($c->req->content->asset->to_file->path, undef, {limit => 1}))[0])->name =~ s/\/$/.$ext/r;
    my ($version) = ($package =~ /([^-]+)\.tar/);
    my ($module) = ($package =~ /^(.*?)-$version\.tar/) if $version;
    $c->param(module => camelize($module)) if $module && !$c->param('module');
    $c->param(version => $version) if $version && !$c->param('version');
    $c->param(package => $package) if $package && !$c->param('package');
    return $c->param('module') && $c->param('version') && $c->param('package');
  });
  $app->helper('index.update' => sub ($c, @files) {
    my $module = $c->param('module');
    my $version = $c->param('version');
    my $package = $c->param('package');
    return unless $module && $version && $package;
    my $package_hash = path($c->hash->file($module, $package));
    for my $file (@files) {
      my $index = b($file->make_basename->slurp)  # make sure the file exists before reading it
        ->split("\n\n")                           # split it into header and body sections
        ->map('split', "\n")                      # split each sections into lines
        ->map(sub{$_ || b});                      # make sure every line has a bytestream
      $index->[$_] ||= c for 0..1;                # make sure each section is a collection
      push @{$index->[1]}, b("$module\t$version\t$package_hash");  # add the new item to the index
      $index->[1] = $index->[1]                   # update the index body
        ->map('split', "\t")                      # split each line into module/version/package
        #->tap(sub{warn sprintf "%s -> pre-sort\n%s", $file, $_->map('join', "\t")->join("\n")->to_string})
        ->sort(sub{"$a->[0]" cmp "$b->[0]" || version->parse("$b->[1]") <=> version->parse("$a->[1]")})  # sort by name asc, version desc
        #->tap(sub{warn sprintf "%s -> post-sort\n%s", $file, $_->map('join', "\t")->join("\n")->to_string})
        ->reduce(sub{                             # clean up the index
          if ($file->basename eq $module) {       # keep all records in the full history index
            push @$a, $b
          }
          else {                                  # keep only the most recent versions of each module in the package details index
            push @$a, $b unless $a->size;
            push @$a, $b if !$a->grep(sub{"$_->[0]" eq "$b->[0]"})->size;
          }
          $a
        }, c)
        #->tap(sub{warn sprintf "%s -> post-reduce\n%s", $file, $_->map('join', "\t")->join("\n")->to_string})
        ->map(sub{$_->join("\t")->to_string})     # reassemble the module/version/package record into a string
        ->uniq                                    # eliminate duplicate lines
        #->tap(sub{warn sprintf "%s -> post-uniq\n%s", $file, $_->join("\n")})
        ;
      $c->log->debug("write $file");
      $index = $index
        ->map('join', "\n")                       # reassemble the lines of each section
        ->join("\n\n")                            # reassemble the complete index
        ->tap(sub{$$_.="\n" unless /\n$/})        # make sure the index ends in a lf
        ->to_string;                              # prepare to save the updated index
      $file->spurt($index);
    }
    return $packages->child(@$package_hash)->make_dirname;
  });

  my $r = $app->app->routes;

  $r->get('/modules/02packages.details.txt.gz' => sub ($c) {
    return $c->reply->json_not_found unless -e $details;
    $c->render(data => gzip $details->slurp);
  })->name('package-details');

  $r->put('/upload/#package/:module/#version' => {package => '', module => '', version => ''} => sub ($c) {
    return $c->reply->json(err => 'file is too big') if $c->req->is_limit_exceeded;
    return $c->reply->json(err => 'empty content') unless $c->req->content;
    return $c->reply->json(err => 'check uploaded failed') unless $c->check_upload;
    my $file = $c->index->update($details, $self->history($c->param('module')));
    return $c->reply->json(err => 'index update failed') unless $file;
    return $c->reply->json(err => "package exists") if -e $file;
    $c->log->debug("write $file");
    my $asset = $c->req->content->asset->move_to($file);
    $c->reply->json(ok => "uploaded $file");
  })->name('package-upload');

  return $self;
}

sub _grep_static_paths ($self, $path) { grep { "$path" eq "$_" } @{$self->app->static->paths} }

1;

=encoding utf8

=head1 NAME

Mojolicious::Plugin::Darkpan - Mojolicious Plugin

=head1 SYNOPSIS

  # Mojolicious
  $self->plugin('Darkpan');

  # Mojolicious::Lite
  plugin 'Darkpan';

=head1 DESCRIPTION

L<Mojolicious::Plugin::Darkpan> is a L<Mojolicious> plugin.

=head1 ATTRIBUTES

L<Mojolicious::Plugin::Darkpan> implements the following attributes.

=head2 app

  my $app = $c->app;
  $c      = $c->app(Mojolicious->new);

A reference back to the application that dispatched to this controller, usually a L<Mojolicious> object. Note that this
attribute is weakened.

  # Use application logger
  $c->app->log->debug('Hello Mojo');

  # Generate path
  my $path = $c->app->home->child('templates', 'foo', 'bar.html.ep');

=head2 config

The configuration HASH for this plugin.

=head2 details

A L<Mojo::File/"path"> to the C<02packages.details.txt> file.

=head2 packages

A L<Mojo::File/"path"> to the C<authors/id> directory.

=head2 public

A L<Mojo::File/"path"> to the C<public> directory, defaults to "public" in the app's home directory. Configure with "public".

=head1 HELPERS

L<Mojolicious::Plugin::Darkpan> implements the following helpers.

=head2 check_upload

  $bool = $c->check_upload;

Check the uploaded file and set the guessed module name, version, and filename (if necessary) by looking at the name of
the first folder in tar file.

=head2 hash->file

  @parts = $c->hash->file($module, $file);

Generate the parts of a hashed path for storing lots of artifacts.

  # qw(M MY MYA my_app-0.01.tar.gz)
  $c->hash->file('MyApp', 'my_app-0.01.tar.gz');

=head2 index->update

  $file = $c->index->update(@files);

Reindex the specified files and return the path to the index file.

  # "/public/authors/id/M/MY/MYA/my_app-0.01.tar.gz"
  $c->index->update('details.txt', 'history/MyApp');

=head2 reply->json

  $c = $c->reply->json({key => 'value'});
  $c = $c->reply->json(key => 'value');

Render a JSON response and include the module, version, and package filename.

  # {ok => 'uploaded', module => 'MyApp', version => '0.01', package => 'my_app-0.01.tar.gz'}
  $c->reply->json(ok => 'uploaded');

=head1 HOOKS

L<Mojolicious::Plugin::Darkpan> uses the following hooks.

=head2 after_static

Log served static files.

=head1 METHODS

L<Mojolicious::Plugin::Darkpan> inherits all methods from
L<Mojolicious::Plugin> and implements the following new ones.

=head2 history

  $path = $plugin->history($module);

Get the path to a module's history index file.

  # "/path/public/v1.0/history/MyApp
  $plugin->history('MyApp');

=head2 register

  $darkpan = $plugin->register(Mojolicious->new, {public => '/path'});

Register plugin in L<Mojolicious> application, and return the L<Mojolicious::Plugin::Darkpan> object.
Adds the "Darkpan::Command" namespace to L<Mojolicious/"commands">.
Adds the configured "public" folder to L<Mojolicious/"static"> paths.

=head1 ROUTES

L<Mojolicious::Plugin::Darkpan> implements the following routes.

=head2 GET /authors/id/*hashed_packages

This route serves the package files.

=head2 GET /modules/02packages.details.txt.gz

This route serves the gzipped 02packages.details.txt file.

=head2 GET /v1.0/history/:module

This route serves the requested module's history index file.

=head2 PUT /upload/#package/:module/#version

This route is for uploading a new package file. If the module and version are not provided they are guessed from the
package file name. If the package file name is not provided it is guessed from the first path in the uploaded tarball.

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<https://mojolicious.org>.

=cut
