#!/usr/bin/perl
use lib qw( /openils/lib/perl5 ); 
use OpenILS::WWW::Exporter qw( /openils/conf/opensrf_core.xml );
use OpenILS::WWW::SuperCat qw( /openils/conf/opensrf_core.xml );
use OpenILS::WWW::AddedContent qw( /openils/conf/opensrf_core.xml );
use OpenILS::WWW::Proxy ('/openils/conf/opensrf_core.xml');
use OpenILS::WWW::Vandelay qw( /openils/conf/opensrf_core.xml );
use OpenILS::WWW::EGWeb ('/openils/conf/oils_web.xml');

# - Uncoment the following 2 lines to make use of the IP redirection code
# - The IP file should to contain a map with the following format:
# - actor.org_unit.shortname <start_ip> <end_ip>
# - e.g.  LIB123 10.0.0.1 10.0.0.254

#use OpenILS::WWW::Redirect qw(/openils/conf/opensrf_core.xml);
#OpenILS::WWW::Redirect->parse_ips_file('/openils/conf/lib_ips.txt');



1;

