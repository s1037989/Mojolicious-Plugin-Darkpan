BEGIN { $ENV{MOJO_LOG_LEVEL} = 'info'; }

use Mojo::Base -strict, -signatures;

use Test::More;
use Mojolicious::Lite -signatures;
use Test::Mojo;

use Mojo::File qw(curfile tempdir);
use Mojo::UserAgent;
use Mojo::Util qw(gunzip gzip);

plugin 'Darkpan' => {public => tempdir};

get '/' => sub ($c) {
  $c->render(text => 'Hello Mojo!');
};

my $t = Test::Mojo->new;

subtest 'app works' => sub {
  $t->get_ok('/')->status_is(200)->content_is('Hello Mojo!')
};

subtest 'no 02packages.details.txt.gz' => sub {
  $t->get_ok('/modules/02packages.details.txt.gz')->status_is(404);
};

subtest 'no history' => sub {
  $t->get_ok('/v1.0/history/MyApp')->status_is(404);
  $t->get_ok('/v1.0/history/Qaz')->status_is(404);
};

subtest 'no packages' => sub {
  $t->head_ok('/authors/id/M/MY/MYA/my_app-0.01.tar.gz')->status_is(404);
  $t->head_ok('/authors/id/Q/QA/QAZ/qaz-1.23.tar.gz')->status_is(404);
  $t->head_ok('/authors/id/Q/QA/QAZ/qaz-1.21.tar.gz')->status_is(404);
};

subtest 'correct uploading' => sub {
  $t->put_ok('/upload' => curfile->sibling('my_app-0.01.tar.gz')->slurp)
    ->status_is(200)
    ->json_has('/ok')
    ->json_hasnt('/err')
    ->json_is('/package' => 'my_app-0.01.tar.gz');
  $t->put_ok('/upload' => curfile->sibling('my_app-0.01.tar.gz')->slurp)
    ->status_is(200)
    ->json_hasnt('/ok')
    ->json_has('/err')
    ->json_is('/package' => 'my_app-0.01.tar.gz');
  $t->put_ok('/upload/qaz-1.23.tar.gz' => curfile->sibling('my_app-0.01.tar.gz')->slurp)
    ->status_is(200)
    ->json_has('/ok')
    ->json_hasnt('/err')
    ->json_is('/package' => 'qaz-1.23.tar.gz');
  $t->put_ok('/upload/qaz-1.21.tar.gz' => curfile->sibling('my_app-0.01.tar.gz')->slurp)
    ->status_is(200)
    ->json_has('/ok')
    ->json_hasnt('/err')
    ->json_is('/package' => 'qaz-1.21.tar.gz');
};

subtest 'correct 02packages.details.txt.gz' => sub {
  $t->get_ok('/modules/02packages.details.txt.gz')
    ->status_is(200)
    ->content_is(gzip "\n\nMyApp\t0.01\tM/MY/MYA/my_app-0.01.tar.gz\nQaz\t1.23\tQ/QA/QAZ/qaz-1.23.tar.gz\n");
};

subtest 'correct history' => sub {
  $t->get_ok('/v1.0/history/MyApp')
    ->status_is(200)
    ->content_is("\n\nMyApp\t0.01\tM/MY/MYA/my_app-0.01.tar.gz\n");
  $t->get_ok('/v1.0/history/Qaz')
    ->status_is(200)
    ->content_is("\n\nQaz\t1.23\tQ/QA/QAZ/qaz-1.23.tar.gz\nQaz\t1.21\tQ/QA/QAZ/qaz-1.21.tar.gz\n");
};

subtest 'correct downloads' => sub {
  $t->head_ok('/authors/id/M/MY/MYA/my_app-0.01.tar.gz')->status_is(200);
  $t->head_ok('/authors/id/Q/QA/QAZ/qaz-1.23.tar.gz')->status_is(200);
};

subtest 'proxy as a darkpan' => sub {
  my $server_url = $t->ua->server->url;
  if ($ENV{TEST_VERBOSE}) {
    diag "Testing Darkpan for cpanm using proxy:";
    diag "\$ HTTP_PROXY=$server_url cpanm Qaz\@0.01";
  }
  $t->ua->proxy->http($server_url);
  $t->head_ok('http://www.cpan.org/v1.0/history/Qaz')
    ->status_is(200)
    ->header_is(Server => 'Mojolicious (Perl)');
};

done_testing();
