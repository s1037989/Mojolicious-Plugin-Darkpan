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

sub register {
  my ($self, $app, $config) = @_;

  my $public = path($config->{public} || $app->home->child('public'))->with_roles('Mojo::File::Role::MakePath');
  push @{$app->static->paths}, $public->to_string unless grep { $public->to_string eq path($_)->to_string } @{$app->static->paths};
  my $details = $public->child('modules', '02packages.details.txt');
  my $history = sub ($module) { $public->child('v1.0', 'history', $module) };
  my $packages = $public->child('authors', 'id');

  $app->hook(after_static => sub ($c) { $c->log->debug($c->req->url->path) });

  $app->helper('reply.json' => sub {
    my $c = shift;
    my $json = {@_>1?@_:%{shift()}, map { $c->param($_) ? ($_ => $c->param($_)) : () } qw(module version package)};
    $c->render(json => $json);
  });
  $app->helper('hash.file' => sub ($c, $m, $p) { $m = uc(camelize($m)); (substr($m, 0, 1), substr($m, 0, 2)||'_', substr($m, 0, 3)||'_', lc($p)) });
  $app->helper('guess.package_name' => sub ($c) {
    my $ext = ((extensions(mimetype($c->req->content->asset->to_file->path)))[0]);
    $ext = "tar.$ext" unless $ext eq 'tar';
    ((Archive::Tar->new->read($c->req->content->asset->to_file->path, undef, {limit => 1}))[0])->name =~ s/\/$/.$ext/r
  });
  $app->helper('check_upload' => sub ($c) {
    my $package = $c->param('package') || $c->guess->package_name;
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
    my $package_hash = path($c->hash->file($module, $package));
    for my $file (@files) {
      my $index = b($file->make_basename->slurp)->split("\n\n")->map('split', "\n")->map(sub{$_ || b});
      $index->[$_] ||= c for 0..1;
      push @{$index->[1]}, b("$module\t$version\t$package_hash");
      $index->[1] = $index->[1]
        ->map('split', "\t")
        #->tap(sub{warn sprintf "%s -> pre-sort\n%s", $file, $_->map('join', "\t")->join("\n")->to_string})
        ->sort(sub{"$a->[0]" cmp "$b->[0]" || version->parse("$b->[1]") <=> version->parse("$a->[1]")})
        #->tap(sub{warn sprintf "%s -> post-sort\n%s", $file, $_->map('join', "\t")->join("\n")->to_string})
        ->reduce(sub{
          if ($file->basename eq $module) {
            push @$a, $b
          }
          else {
            push @$a, $b unless $a->size;
            push @$a, $b if !$a->grep(sub{"$_->[0]" eq "$b->[0]"})->size;
          }
          $a
        }, c)
        #->tap(sub{warn sprintf "%s -> post-reduce\n%s", $file, $_->map('join', "\t")->join("\n")->to_string})
        ->map(sub{$_->join("\t")->to_string})
        ->uniq
        #->tap(sub{warn sprintf "%s -> post-uniq\n%s", $file, $_->join("\n")})
        ;
      $c->log->debug("write $file");
      $file->spurt($index->map('join', "\n")->join("\n\n")->tap(sub{$$_.="\n" unless /\n$/})->to_string);
    }
    return $package_hash;
  });

  my $r = $app->app->routes;

  $r->get('/modules/02packages.details.txt.gz' => sub ($c) {
    return $c->reply->json_not_found unless -e $details;
    $c->render(data => gzip $details->slurp);
  })->name('package-details');

  $r->put('/upload/#package/:module/#version' => {package => '', module => '', version => ''} => sub ($c) {
    return $c->reply->json(err => 'file is too big') if $c->req->is_limit_exceeded;
    #warn $c->dumper($c->req);
    return $c->reply->json(err => 'empty content') unless $c->req->content;
    return $c->reply->json(err => 'check uploaded failed') unless $c->check_upload;
    my $package_hash = $c->index->update($details, $history->($c->param('module')));
    return $c->reply->json(err => 'index update failed') unless $package_hash;
    my $file = $packages->child(@$package_hash)->make_dirname;
    $c->log->debug("write $file");
    return $c->reply->json(err => "package exists") if -e $file;
    my $asset = $c->req->content->asset->move_to($file);
    $c->reply->json(ok => "uploaded $file");
  })->name('package-upload');

}

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

=head1 METHODS

L<Mojolicious::Plugin::Darkpan> inherits all methods from
L<Mojolicious::Plugin> and implements the following new ones.

=head2 register

  $plugin->register(Mojolicious->new);

Register plugin in L<Mojolicious> application.

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<https://mojolicious.org>.

=cut
