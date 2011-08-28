#!/usr/bin/env perl

use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/extlib/lib/perl5";
use lib "$FindBin::Bin/lib";
use Isucon;
use Cache::Memcached::Fast;

my $app = Isucon->psgi();

my $cache;
sub {
    $cache ||= Cache::Memcached::Fast->new({
        servers => ['127.0.0.1:11211'],
    });

    my $env = shift;
    $env->{HTTP_HOST} = '192.168.1.80';
    my $res = $app->($env);

    if ($env->{REQUEST_METHOD} eq 'GET' && $res->[0] == 200) {
        my $content = $res->[2];
        $content = join '', @$content if ref $content;
        $cache->set($env->{REQUEST_URI}, $content, 5);
    }
    elsif ($env->{REQUEST_METHOD} eq 'POST') {
        my %header = @{$res->[1]};
        if (my $location = $header{Location}) {
            my $path = $location->path_query;
            warn "$path, $env->{REQUEST_URI}";
            $cache->delete($path);
            $cache->delete($env->{REQUEST_URI});
            $cache->delete('/');
        }
    }
    
    return $res;
};
