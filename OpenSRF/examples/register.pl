#!/usr/bin/perl
# ----------------------------------------------------------------------
# Utility script for registring users on a jabber server.  
# ----------------------------------------------------------------------
use Net::Jabber;
use strict;

if (@ARGV < 4) {
    print "\nperl $0 <server> <port> <username> <password> \n\n";
    exit(0);
}

my $server = $ARGV[0];
my $port = $ARGV[1];
my $username = $ARGV[2];
my $password = $ARGV[3];
my $resource = "test_${server}_$$";

my $connection = Net::Jabber::Client->new;

my $status = $connection->Connect(hostname=>$server, port=>$port);

my @stat = $connection->RegisterSend(
	$server, 
	username => $username,
	password => $password );


print "Register results : @stat\n";


if (!defined($status)) {
    print "ERROR:  Jabber server is down or connection was not allowed.\n";
    print "        ($!)\n";
    exit(0);
}

my @result = $connection->AuthSend(
	username=>$username, password=>$password, resource=>$resource);

if ($result[0] ne "ok") {
    print "ERROR: Authorization failed: $result[0] - $result[1]\n";
    exit(0);
}

print "Logged in OK to $server:$port\nRegistration succeeded for $username\@$server!\n";

$connection->Disconnect();


