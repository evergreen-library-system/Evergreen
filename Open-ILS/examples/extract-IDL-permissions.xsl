<?xml version="1.0" encoding="UTF-8"?>
<xsl:stylesheet version="1.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform" xmlns="http://opensrf.org/spec/IDL/base/v1" xmlns:oils_persist="http://open-ils.org/spec/opensrf/IDL/persistence/v1" xmlns:oils_obj="http://open-ils.org/spec/opensrf/IDL/objects/v1" xmlns:reporter="http://open-ils.org/spec/opensrf/IDL/reporter/v1" xmlns:permacrud="http://open-ils.org/spec/opensrf/IDL/permacrud/v1">
	<xsl:output method="text" indent="no" omit-xml-declaration="yes"/>

<!--
	USAGE:
		xsltproc extract-IDL-permissions.xsl fm_IDL.xml|perl -e 'while(<>){s/^\s+(.*)\s+$/$1/o;print("$1\n")unless(/^\s*$/ || /\s+/)}'|sort -u|less
-->

	<xsl:template match="//permacrud:actions/*">
		<xsl:if test="@permission">
			<xsl:call-template name="output-tokens">
				<xsl:with-param name="list"><xsl:value-of select="@permission"/></xsl:with-param>
			</xsl:call-template>
		</xsl:if>
	</xsl:template>

	<xsl:template name="output-tokens">
		<xsl:param name="list" />
		<xsl:variable name="newlist" select="normalize-space($list)" />
		<xsl:variable name="first" select="substring-before($newlist, ' ')" />
		<xsl:variable name="remaining" select="substring-after($list, ' ')" />
		<xsl:choose test="$first">
			<xsl:when test="$first">
				<xsl:value-of select="$first" /><xsl:text>
</xsl:text>
				<xsl:if test="$remaining">
					<xsl:call-template name="output-tokens">
						<xsl:with-param name="list" select="$remaining" />
					</xsl:call-template>
				</xsl:if>
			</xsl:when>
			<xsl:otherwise>
				<xsl:value-of select="$list" />
			</xsl:otherwise>
		</xsl:choose>
	</xsl:template>

</xsl:stylesheet>
