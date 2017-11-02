<?xml version="1.0" encoding="UTF-8"?>
<xsl:stylesheet version="1.0" xmlns:oai_dc="http://www.openarchives.org/OAI/2.0/oai_dc/" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:xsl="http://www.w3.org/1999/XSL/Transform">
	<xsl:import href="MARC21slim2OAIDC.xsl"/>
	<xsl:output omit-xml-declaration="yes"/>

    <xsl:template match="/">
			<oai_dc:dc xsi:schemaLocation="http://www.openarchives.org/OAI/2.0/oai_dc/ http://www.openarchives.org/OAI/2.0/oai_dc.xsd"
                       xmlns:dc="http://purl.org/dc/elements/1.1/">
				<xsl:apply-templates/>
			</oai_dc:dc>
	</xsl:template>

</xsl:stylesheet>