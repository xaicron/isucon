package Isucon;

use strict;
use warnings;
use utf8;
use Kossy;
use DBI;
use JSON;
use Cache::Memcached::Fast;

our $VERSION = 0.01;

sub load_config {
    my $self = shift;
    return $self->{_config} if $self->{_config};
    open( my $fh, '<', $self->root_dir . '/../config/hosts.json') or die $!;
    local $/;
    my $json = <$fh>;
    $self->{_config} = decode_json($json);    
}

sub dbh {
    my $self = shift;
    my $config = $self->load_config;
    my $host = $config->{servers}->{database}->[0] || '127.0.0.1';
    DBI->connect_cached('dbi:mysql:isucon;host='.$host,'isuconapp','isunageruna',{
        RaiseError => 1,
        PrintError => 0,
        ShowErrorStatement => 1,
        AutoInactiveDestroy => 1,
        mysql_enable_utf8 => 1
    });
}

my $cache;
sub cache {
    $cache ||= Cache::Memcached::Fast->new({
        servers => ['127.0.0.1:11211'],
    });
}

filter 'recent_commented_articles' => sub {
    my $app = shift;
    sub {
        my ( $self, $c )  = @_;
        my $rows = $self->cache->get('recent_commented_articles');
        unless ($rows) {
            $rows = $self->dbh->selectall_arrayref(
                'SELECT id, title FROM article ORDER BY commented_at DESC LIMIT 10',
                { Slice => {} });
            $self->cache->set('recent_commented_articles', $rows);
        }
        $c->stash->{recent_commented_articles} = $rows;
        $app->($self,$c);
    }
};

get '/' => [qw/recent_commented_articles/] => sub {
    my ( $self, $c )  = @_;
    my $rows = $self->dbh->selectall_arrayref(
        'SELECT id,title,body,created_at FROM article ORDER BY id DESC LIMIT 10',
        { Slice => {} });
    $c->render('index.tx', { articles => $rows });
};

get '/article/:articleid' => [qw/recent_commented_articles/] => sub {
    my ( $self, $c )  = @_;
    my $article = $self->dbh->selectrow_hashref(
        'SELECT id,title,body,created_at FROM article WHERE id=?',
        {}, $c->args->{articleid});
    my $comments = $self->dbh->selectall_arrayref(
        'SELECT name,body,created_at FROM comment WHERE article=? ORDER BY id', 
        { Slice => {} }, $c->args->{articleid});
    $c->render('article.tx', { article => $article, comments => $comments });
};

get '/post' => [qw/recent_commented_articles/] => sub {
    my ( $self, $c )  = @_;
    $c->render('post.tx');
};

post '/post' => sub {
    my ( $self, $c )  = @_;
    my $sth = $self->dbh->prepare('INSERT INTO article SET title = ?, body = ?');
    $sth->execute($c->req->param('title'), $c->req->param('body'));
    $c->redirect($c->req->uri_for('/'));
};

post '/comment/:articleid' => sub {
    my ( $self, $c )  = @_;

    do {
        my $sth = $self->dbh->prepare('INSERT INTO comment SET article = ?, name =?, body = ?');
        $sth->execute(
            $c->args->{articleid},
            $c->req->param('name'),
            $c->req->param('body'),
        );
    };
    do {
        my $sth = $self->dbh->prepare('UPDATE article SET commented_at = UNIX_TIMESTAMP() WHERE id = ?');
        $sth->execute($c->args->{articleid});
    };
    $self->cache->delete('recent_commented_articles');
    $c->redirect($c->req->uri_for('/article/'.$c->args->{articleid}));
};

1;

