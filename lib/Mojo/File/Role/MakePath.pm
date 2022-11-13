package Mojo::File::Role::MakePath;
use Mojo::Base -role, -signatures;

requires 'dirname';

sub make_dirname ($self) { shift->tap(sub{$_->dirname->tap(sub{-e $_ or $_->make_path})}) }
sub make_basename ($self) { shift->tap(sub{$_->dirname->tap(sub{-e $_ or $_->make_path}); -e $_ or $_->touch}) }

1;