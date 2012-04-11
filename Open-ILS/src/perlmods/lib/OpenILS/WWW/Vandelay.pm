package OpenILS::WWW::Vandelay;
use strict;
use warnings;
use bytes;

use Apache2::Log;
use Apache2::Const -compile => qw(OK REDIRECT DECLINED NOT_FOUND FORBIDDEN :log);
use APR::Const    -compile => qw(:error SUCCESS);
use APR::Table;

use Apache2::RequestRec ();
use Apache2::RequestIO ();
use Apache2::RequestUtil;
use CGI;
use Data::Dumper;
use Text::CSV;

use OpenSRF::EX qw(:try);
use OpenSRF::Utils::Cache;
use OpenSRF::System;
use OpenSRF::AppSession;
use XML::LibXML;

use OpenILS::Utils::Fieldmapper;
use OpenSRF::Utils::Logger qw/$logger/;

use MARC::Record;
use MARC::File::XML ( BinaryEncoding => 'UTF-8' );

use MIME::Base64;
use Digest::MD5 qw/md5_hex/;
use OpenSRF::Utils::SettingsClient;

use UNIVERSAL::require;

our @formats = qw/USMARC UNIMARC XML BRE/;
my $MAX_FILE_SIZE = 10737418240; #10G
my $FILE_READ_SIZE = 4096;

# set the bootstrap config and template include directory when
# this module is loaded
my $bootstrap;

sub import {
        my $self = shift;
        $bootstrap = shift;
}


sub child_init {
        OpenSRF::System->bootstrap_client( config_file => $bootstrap );
        return Apache2::Const::OK;
}

sub spool_marc {
	my $r = shift;
	my $cgi = new CGI;

	my $auth = $cgi->param('ses') || $cgi->cookie('ses');

	unless(verify_login($auth)) {
        $logger->error("authentication failed on vandelay record import: $auth");
	    return Apache2::Const::FORBIDDEN;
    }

    my $data_fingerprint = '';
	my $purpose = $cgi->param('purpose') || '';
	my $infile = $cgi->param('marc_upload') || '';
    my $bib_source = $cgi->param('bib_source') || '';

    $logger->debug("purpose = $purpose, infile = $infile, bib_source = $bib_source");

	my $conf = OpenSRF::Utils::SettingsClient->new;
	my $dir = $conf->config_value(
        apps => 'open-ils.vandelay' => app_settings => databases => 'importer');

    unless(-w $dir) {
        $logger->error("We need some place to store our MARC files");
	    return Apache2::Const::FORBIDDEN;
    }

    if($infile and -e $infile) {
        my ($total_bytes, $buf, $bytes) = (0);
	    $data_fingerprint = md5_hex(time."$$".rand());
        my $outfile = "$dir/$data_fingerprint.mrc";

        unless(open(OUTFILE, ">$outfile")) {
            $logger->error("unable to open MARC file [$outfile] for writing: $@");
	        return Apache2::Const::FORBIDDEN;
        }

        while($bytes = sysread($infile, $buf, $FILE_READ_SIZE)) {
            $total_bytes += $bytes;
            if($total_bytes >= $MAX_FILE_SIZE) {
                close(OUTFILE);
                unlink $outfile;
                $logger->error("import exceeded upload size: $MAX_FILE_SIZE");
	            return Apache2::Const::FORBIDDEN;
            }
            print OUTFILE $buf;
        }

        close(OUTFILE);

	    OpenSRF::Utils::Cache->new->put_cache(
		    'vandelay_import_spool_' . $data_fingerprint,
		    {   purpose => $purpose, 
                path => $outfile,
                bib_source => $bib_source,
            }
	    );
    }

    $logger->info("uploaded MARC batch with key $data_fingerprint");
    $r->content_type('text/plain; charset=utf-8');
	print "$data_fingerprint";
	return Apache2::Const::OK;
}

sub verify_login {
        my $auth_token = shift;
        return undef unless $auth_token;

        my $user = OpenSRF::AppSession
                ->create("open-ils.auth")
                ->request( "open-ils.auth.session.retrieve", $auth_token )
                ->gather(1);

        if (ref($user) eq 'HASH' && $user->{ilsevent} == 1001) {
                return undef;
        }

        return $user if ref($user);
        return undef;
}

1;
