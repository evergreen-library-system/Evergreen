package OpenILS::Application::WORM;
use XML::LibXML;
use XML::LibXSLT;

use OpenSRF::Application;
use base qw/OpenSRF::Application/;
use vars qw/$xml_parser $utf8izer/;

use OpenILS::Utils::FlatXML;

sub initialize {
	$xml_parser = XML::LibXML->new;
	$utf8izer = XML::LibXSLT->new->parse_stylesheet( $xml_parser->parse_string(<<"	XSLT") );
		<xsl:stylesheet version="1.0"
				xmlns:xlink="http://www.w3.org/1999/xlink"
				xmlns:marc="http://www.loc.gov/MARC21/slim"
				xmlns:xsl="http://www.w3.org/1999/XSL/Transform">

			<xsl:template match="/">
				<xsl:copy-of select="."/>
			</xsl:template>

		</xsl:stylesheet>
	XSLT
}

sub child_init {
	# This will force the introspection dance
	__PACKAGE__->method_lookup('open-ils.nunya');
}

sub nodeset_to_encoded_xml {
	my $self = shift;
	my $client = shift;
	my $nodeset = shift;

	my $fxml = new OpenILS::Utils::FlatXML ( nodeset => $nodeset );

	my $xml = $fxml->nodeset_to_xml->toString;
	$xml =~ s/[\x01\x02\x03\x04\x05\x06\x07\x08\x0b\x0c\x0e\x0f\x10\x11\x12\x13\x14\x15\x16\x17\x18\x19\x1a\x1b\x1c\x1d\x1e\x1f]//gsom;
	$xml =~ s/>[\x0a\x0d\s]+</></gosm;
	$xml =~ s/[\x09]/\\t/ogsm;
	
	$xml =
	$utf8izer->output_string(
		$utf8izer->transform(
			$xml_parser->parse_string( $xml )
		)
	);
}
__PACKAGE__->register_method(
	method		=> 'nodeset_to_encoded_xml',
	api_name	=> 'open-ils.worm.nodeset.encoded_xml',
	api_level	=> 0,
	argc		=> 1,
);


1;
