<?xml version="1.0" encoding="UTF-8"?>
<xsl:stylesheet version="1.0" xmlns:marc="http://www.loc.gov/MARC21/slim" xmlns:xsl="http://www.w3.org/1999/XSL/Transform">
	<xsl:output method="html"/>
	
	<xsl:template match="/">
		<html>
			<head>
				<title>MARC</title>
				<meta http-equiv="Content-Type" content="text/html;charset=UTF-8"/>

				<style>

					.marc_table {}
					.marc_tag_row {}
					.marc_tag_data {}
					.marc_tag_col {}
					.marc_tag_ind {}
					.marc_subfields {}
					.marc_subfield_code { 
						color: var(--primary); 
						padding-left: 5px;
						padding-right: 5px; 
					}

				</style>

				<link href='/css/opac_marc.css' rel='stylesheet' type='text/css'></link>
			</head>
			<body>
				<div><button onclick='window.print();'>Print Page</button></div>
				<xsl:apply-templates/>
			</body>
		</html>
	</xsl:template>
	
	<xsl:template match="marc:record">
		<table class='marc_table'>
			<tr class='marc_tag_row'>
				<th class='marc_tag_col' NOWRAP="TRUE">
					LDR
				</th>
				<td class='marc_tag_data' COLSPAN='3'>
					<xsl:value-of select="marc:leader"/>
				</td>
			</tr>
			<xsl:apply-templates select="marc:datafield|marc:controlfield"/>
		</table>
	</xsl:template>
	
	<xsl:template match="marc:controlfield">
		<tr class='marc_tag_row'>
			<th class='marc_tag_col' NOWRAP="TRUE">
				<xsl:value-of select="@tag"/>
			</th>
			<td class='marc_tag_data' COLSPAN='3'>
				<xsl:value-of select="."/>
			</td>
		</tr>
	</xsl:template>
	
	<xsl:template match="marc:datafield">
		<tr class='marc_tag_row'>
			<th class='marc_tag_col' NOWRAP="TRUE">
				<xsl:value-of select="@tag"/>
			</th>
			<td class='marc_tag_ind1'>
				<xsl:value-of select="@ind1"/>
			</td>

			<td class='marc_tag_ind2'>
				<xsl:value-of select="@ind2"/>
			</td>

			<td class='marc_subfields'>
				<xsl:apply-templates select="marc:subfield"/>
			</td>
		</tr>
	</xsl:template>
	
	<xsl:template match="marc:subfield">
		<span class='marc_subfield_code' > 
			&#8225;<xsl:value-of select="@code"/>
		</span><xsl:value-of select="."/>	
	</xsl:template>

</xsl:stylesheet>

<!-- Stylus Studio meta-information - (c)1998-2002 eXcelon Corp.
<metaInformation>
<scenarios ><scenario default="no" name="Ray Charles" userelativepaths="yes" externalpreview="no" url="..\xml\MARC21slim\raycharles.xml" htmlbaseurl="" outputurl="" processortype="internal" commandline="" additionalpath="" additionalclasspath="" postprocessortype="none" postprocesscommandline="" postprocessadditionalpath="" postprocessgeneratedext=""/><scenario default="yes" name="s7" userelativepaths="yes" externalpreview="no" url="..\ifla\sally7.xml" htmlbaseurl="" outputurl="" processortype="internal" commandline="" additionalpath="" additionalclasspath="" postprocessortype="none" postprocesscommandline="" postprocessadditionalpath="" postprocessgeneratedext=""/></scenarios><MapperInfo srcSchemaPath="" srcSchemaRoot="" srcSchemaPathIsRelative="yes" srcSchemaInterpretAsXML="no" destSchemaPath="" destSchemaRoot="" destSchemaPathIsRelative="yes" destSchemaInterpretAsXML="no"/>
</metaInformation>
-->
