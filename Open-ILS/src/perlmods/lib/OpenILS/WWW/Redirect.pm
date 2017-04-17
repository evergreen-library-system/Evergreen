package OpenILS::WWW::Redirect;
use strict; use warnings;

use Socket;
use Apache2::Log;
use Apache2::Const -compile => qw(OK REDIRECT :log);
use APR::Const    -compile => qw(:error SUCCESS);
use Apache2::RequestRec ();
use Apache2::RequestIO ();
use CGI ();

use OpenSRF::AppSession;
use OpenSRF::System;
use OpenSRF::Utils::Logger qw/$logger/;
use Net::IP;

use vars '$lib_ips_hash';
my $lib_ips_hash;

my $bootstrap_config_file;
sub import {
    my( $self, $config ) = @_;
    $bootstrap_config_file = $config;
}

sub init {
    OpenSRF::System->bootstrap_client( config_file => $bootstrap_config_file );
}

sub parse_ips_file {
    my $class = shift;
    my $ips_file = shift;

    if( open(F, $ips_file) ) {

       while( my $data = <F> ) {
         chomp($data);

         my ($shortname, $ip1, $ip2, $skin, $domain) = split(/\s+/, $data);
         next unless ($shortname and $ip1 and $ip2);

         $lib_ips_hash->{$shortname} = [] unless $lib_ips_hash->{$shortname};
         push( @{$lib_ips_hash->{$shortname}}, [ $ip1, $ip2, $skin, $domain ] );
       }

       close(F);

    } else {
        $logger->error("Unable to open lib IP redirector file $ips_file");
    }
}


my %org_cache;
sub handler {
    my $apache = shift;

    my $cgi = CGI->new( $apache );
    my $hostname = $cgi->server_name();
    my $proto = ($cgi->https) ? 'https' : 'http';
    my $user_ip = $ENV{REMOTE_ADDR};

    # Extract the port number from the user requested URL.
    my $port = '';
    my $cgiurl = $cgi->url;
    if ($cgiurl =~ m|https?://[^:]+:\d+/|) {
        ($port = $cgiurl) =~ s|https?://[^:]+:(\d+).*|$1|;
    }

    # Apache config values
    my $skin = $apache->dir_config('OILSRedirectSkin') || 'default';
    my $depth = $apache->dir_config('OILSRedirectDepth');
    my $locale = $apache->dir_config('OILSRedirectLocale') || 'en-US';
    my $use_tt = ($apache->dir_config('OILSRedirectTpac') || '') =~ /true/i;
    my $physical_loc;

    $apache->log->debug("Redirector sees client frim $user_ip");

    # parse the IP file
    my ($shortname, $nskin, $nhostname) = redirect_libs($user_ip);

    if ($shortname) { # we have a config

        # Read any override vars from the ips txt file
        if ($nskin =~ m/[^\s]/) { $skin = $nskin; }
        if ($nhostname =~ m/[^\s]/) { $hostname = $nhostname; }

        if($org_cache{$shortname}) {
            $physical_loc = $org_cache{$shortname};

        } else {

            my $session = OpenSRF::AppSession->create("open-ils.actor");
            my $org = $session->request(
                'open-ils.actor.org_unit.retrieve_by_shortname',
                $shortname)->gather(1);

            $org_cache{$shortname} = $physical_loc = $org->id if $org;
        }
    }

    # only encode the port if a nonstandard port was requested.
    my $url = $port ? "$proto://$hostname:$port" : "$proto://$hostname";

    if($use_tt) {

        $url .= "/eg/opac/home";
        $url .= "?physical_loc=$physical_loc" if $physical_loc;

=head1 potential locale/skin implementation

        if($locale ne 'en-US') {
            $apache->headers_out->add(
                "Set-Cookie" => $cgi->cookie(
                    -name => "oils:locale", # see EGWeb.pm
                    -path => "/eg",
                    -value => $locale,
                    -expires => undef
                )
            );
        }

        if($skin ne 'default') {
            $apache->headers_out->add(
                "Set-Cookie" => $cgi->cookie(
                    -name => "oils:skin", # see EGWeb.pm
                    -path => "/eg",
                    -value => $skin,
                    -expires => undef
                )
            );
        }
=cut

    } else {
        $url .= "/opac/$locale/skin/$skin/xml/index.xml";
        if($physical_loc) {
            $url .= "?ol=" . $physical_loc;
            $url .= "&d=$depth" if defined $depth;
        }
    }

    $logger->info("Apache redirecting $user_ip to $url");
    $apache->headers_out->add('Location' => "$url");
    return Apache2::Const::REDIRECT;
}

sub redirect_libs {
    my $source_ip = new Net::IP (shift) or return 0;

    # do this the linear way for now...
    for my $shortname (keys %$lib_ips_hash) {

        for my $block (@{$lib_ips_hash->{$shortname}}) {

            $logger->debug("Checking whether " . $source_ip->ip() . " is in the range " . $block->[0] . " to " . $block->[1]);
            if(defined($block->[0]) && defined($block->[1]) ) {
                my $range = new Net::IP( $block->[0] . ' - ' . $block->[1] );
                if( $source_ip->overlaps($range)==$IP_A_IN_B_OVERLAP ||
                    $source_ip->overlaps($range)==$IP_IDENTICAL ) {
                    return ($shortname, $block->[2] || '', $block->[3] || '');
                }
            }
        }
    }
    return 0;
}

1;
