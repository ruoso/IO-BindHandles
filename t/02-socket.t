#!/usr/bin/perl
use strict;
use warnings;

use IO::BindHandles;
use IO::Handle;
use IO::Socket::UNIX;

# in this test we'll build a server that echoes uppercase output, a
# client that posts a set of lines and a proxy that should bind all
# the handles.

my $socket_name;
BEGIN {
    $socket_name = 't/02-socket.sock';
    unlink $socket_name;
}
END {
    unlink $socket_name;
}

my $server_pid = fork();
if ($server_pid == 0) {
    # this is our server that will keep buffer for a while...
    my $sock = IO::Socket::UNIX->new( Local => $socket_name, Listen => 1 ) or die $!;
    my $sock_c = $sock->accept() or die $!;
    my @buffer;
    my $count = 0;
    #warn "[SERVER] before loop.\n";
    while (my $input = $sock_c->getline()) {
        chomp $input;
        #warn "[SERVER] got $input.\n";
        push @buffer, uc($input);
        if ($count++ & 1) {
            #warn "[SERVER] print.\n";
            $sock_c->print(shift(@buffer)."\n");
        }
        last if $input eq 'case';
    }
    #warn "[SERVER] after loop.\n";
    $sock_c->print($_."\n") for @buffer;
    #warn "[SERVER] after print.\n";
    exit 0;
} elsif (not defined $server_pid) {
    die 'Failed to fork server side.';
}

# The STDIN/STDOUT pipes for our client...
my ($cli_stdin_r, $cli_stdin_w, $cli_stdout_r, $cli_stdout_w) = map { IO::Handle->new() } 1..4;
pipe($cli_stdin_r, $cli_stdin_w);
pipe($cli_stdout_r, $cli_stdout_w);
$cli_stdin_r->autoflush(1);
$cli_stdin_w->autoflush(1);
$cli_stdout_r->autoflush(1);
$cli_stdout_w->autoflush(1);

my $client_pid = fork();
if ($client_pid == 0) {
    require Test::More;
    Test::More->import(tests => 12);
    $cli_stdin_r->close;
    $cli_stdout_w->close;
    # this is our client...
    # let's sleep 2 seconds so the proxy starts...
    my @text = qw(this is our test set of strings to be sent lower case);
    #warn "[CLIENT] starting loop.\n";
    foreach my $l (@text) {
        #warn "[CLIENT] wrote line $l.\n";
        $cli_stdin_w->print($l."\n");
    }
    #warn "[CLIENT] out of write loop.\n";
    $cli_stdin_w->close();
    my @ret;
    while (my $l = $cli_stdout_r->getline()) {
        chomp $l;
        #warn "[CLIENT] got line $l.\n";
        push @ret, $l;
    }
    #warn "[CLIENT] read it all.\n";
    is($ret[$_], uc($text[$_])) for 0..$#text;
    exit;
} elsif (not defined $client_pid) {
    die 'Failed to fork client side.';
};

$cli_stdin_w->close;
$cli_stdout_r->close;

# we sleep to give time for the server to start...
sleep 1;

# we now finally setup our proxy
my $sock = IO::Socket::UNIX->new( Peer => $socket_name ) or die $!;
$sock->autoflush(1);
my $bh = IO::BindHandles->new
  ( handles => [
                $cli_stdin_r, $sock,  # read from cli stdin, write to socket
                $sock, $cli_stdout_w, # read from socket, write to cli stdout
               ]
  );

while ($bh->bound()) {
    $bh->rwcycle();
}


$cli_stdin_r->close();
$cli_stdout_w->close();
$sock->close();

waitpid $server_pid, 0;
waitpid $client_pid, 0;
exit 0;
