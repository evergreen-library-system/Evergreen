#!/usr/bin/perl
# Tool for migrating SIP accounts found in oils_sip.xml into the database
# Example: 
# ./migrate-sip-accounts.pl /openils/conf/oils_sip.xml > accounts.sql
#
use strict;
use warnings;
use XML::LibXML;

my $file = $ARGV[0];

die "USAGE: $0 /openils/conf/oils_sip.xml > accounts.sql\n" unless $file;

my $doc = XML::LibXML->new->parse_file($file);

my @accounts = $doc->documentElement->findnodes("//*[local-name()='login']");

print "BEGIN;\n";

for my $account (@accounts) {
    my $username = $account->getAttribute('id');
    my $workstation = $account->getAttribute('location');
    my $password = $account->getAttribute('password');
    my $actwho = $account->getAttribute('activity_who');

    print <<SQL;
INSERT INTO sip.account (enabled, setting_group, sip_username, usr)
VALUES (TRUE, 1, '$username', (SELECT id FROM actor.usr WHERE usrname = '$username'));
SQL

    if ($workstation) {
        print <<SQL;
UPDATE sip.account SET workstation = (SELECT id FROM actor.workstation WHERE name = '$workstation') WHERE sip_username = '$username';
SQL
    }

    if ($actwho) {
        print <<SQL;
UPDATE sip.account SET activity_who = '$actwho' WHERE sip_username = '$username';
SQL
    }

        print <<SQL;
SELECT actor.change_password((SELECT id FROM actor.usr WHERE usrname = '$username'), '$password', 'sip2')
FROM actor.usr WHERE usrname = '$username';
SQL
}

print "COMMIT;\n";


