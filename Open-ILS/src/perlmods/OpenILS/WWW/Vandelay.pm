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
use MARC::File::XML;

use MIME::Base64;
use Digest::MD5 qw/md5_hex/;

use UNIVERSAL::require;

our @formats = qw/USMARC UNIMARC XML BRE/;

# set the bootstrap config and template include directory when
# this module is loaded
my $bootstrap;

sub import {
        my $self = shift;
        $bootstrap = shift;
}


sub child_init {
        OpenSRF::System->bootstrap_client( config_file => $bootstrap );
}

sub spool_marc {
	my $r = shift;
	my $cgi = new CGI;

	my $auth = $cgi->param('ses') || $cgi->cookie('ses');

	return Apache2::Const::FORBIDDEN unless verify_login($auth);


	my $purpose = $cgi->param('purpose');
	my $file = $cgi->param('marc_upload');
	my $filename = "$file";

	my $data = join '', (<$file>);
	$data = encode_base64($data);

	my $data_fingerprint = md5_hex($data);

	OpenSRF::Utils::Cache->new->put_cache(
		'vandelay_import_spool_' . $data_fingerprint,
		{ purpose => $purpose, marc => $data }
	);

	print "Content-type: text/plain; charset=utf-8\n\n$data_fingerprint";

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
