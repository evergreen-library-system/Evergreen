#!/usr/bin/perl

#----------------------------------------------------------------
# Simple example
#----------------------------------------------------------------

require '../oils_header.pl';
use strict; use warnings;

use Getopt::Long;

sub usage {
    return <<END_OF_USAGE;
$0 [-h] --login=UserName --password==MyPass [OPTIONS] [Transaction data]

Required Arguments:
    -l --login      Assigned by your processor API (specified in -t)
    -p --password   Assigned by your processor API (specified in -t)
    -o --org-unit   What library/branch is making this payment (numeric)

Options:
    -t --target       Payment processor (default PayPal)
    -s --signature    A "long password" required by PayPal in leiu of certificates
    -r --server       Use a specific server with a processor (AuthorizeNet)
    -c --config_file  opensrf_core.xml file (default /openils/conf/opensrf_core.xml)

Transaction data:
    -a --amount    Monetary value, no dollar sign, default a random value under 25.00
    -i --id        Patron ID#, default 5 (for no reason)
    -n --number    Credit card number to be charged
    -x --expires   Date (MM-YYYY) of card expiration, default 12-2014

Example:

$0  --login=seller_1254418209_biz_api1.esilibrary.com \\
    --password=1254618222 \\
    --signature=AiPC9xjkCyDFQXbSkoZcgqH3hpacAVPVw5GcZgNKVA9SGKcbrqLuhLks \\
    --amount=32.75 \\
    --id=13042

END_OF_USAGE
}

### DEFAULTS
my $config    = '/openils/conf/opensrf_core.xml';
my $processor = 'PayPal';
my $number    = '4123000011112228';
my $expires   = '12-2014';
my $id        = 5;

### Empties
my ($login, $password, $ou, $signature, $help, $amount, $server);

GetOptions(
    'config_file=s' => \$config,
    'target=s'      => \$processor,
    'org-unit=i'    => \$ou,
    'login=s'       => \$login,
    'password=s'    => \$password,
    's|signature=s' => \$signature,
    'amount=f'      => \$amount,
    'id=i'          => \$id,
    'number=s'      => \$number,
    'x|expires=s'   => \$expires,
    'r|server=s'    => \$server,
    'help|?'        => \$help,
);

$help and print usage and exit;

unless ($login and $processor and $password and $ou) {
    print usage;
    exit;
}
osrf_connect($config);

$amount or $amount = int(rand(25)) . '.' . sprintf("%02d", int(rand(99)));

print <<END_OF_DUMP;
Attempting transaction:
\{
    processor => $processor,
        login => $login,
     password => $password,
    signature => $signature,
           ou => $ou,
       amount => $amount,
           cc => $number,
   expiration => $expires,
       server => $server,
     testmode => 1,
    patron_id => $id,
      country => US,
  description => test transaction processid $$
\}

END_OF_DUMP

my( $user, $evt ) = simplereq('open-ils.credit', 'open-ils.credit.process', 
{
    processor => $processor,
        login => $login,
     password => $password,
    signature => $signature,
           ou => $ou,
       amount => $amount,
           cc => $number,
   expiration => $expires,
       server => $server,
     testmode => 1,
    patron_id => $id,
      country => "US",
  description => "test transaction processid $$"
}
);
oils_event_die($evt); # this user was not found / not all methods return events..
print debug($user);

