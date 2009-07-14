<?xml version="1.0" encoding="UTF-8"?>
<xsl:stylesheet version="1.0" xmlns:marc="http://www.loc.gov/MARC21/slim" xmlns:xsl="http://www.w3.org/1999/XSL/Transform" exclude-result-prefixes="marc">
    <xsl:output method="text"/>

    <xsl:template match="marc:record">
       <xsl:text>&#10;LEADER </xsl:text>
       <xsl:value-of select="marc:leader"/>
        
        <xsl:for-each select="marc:controlfield">
            <xsl:text>&#10;</xsl:text>
            <xsl:value-of select="@tag"/>
            <xsl:text>    </xsl:text>
            <xsl:value-of select="marc:controlfield"/>
            <xsl:value-of select="."/>
        </xsl:for-each>

        <xsl:for-each select="marc:datafield">
            <xsl:text>&#10;</xsl:text>
            <xsl:value-of select="@tag"/>
            <xsl:text> </xsl:text>
            <xsl:value-of select="@ind1"/>
            <xsl:value-of select="@ind2"/>
            <xsl:text> </xsl:text>
            <xsl:for-each select="marc:subfield">
                <xsl:if test="@code != 'a'">
                    <xsl:text>|</xsl:text>
                    <xsl:value-of select="@code"/>
                </xsl:if>
                <xsl:value-of select="."/>
            </xsl:for-each>
        </xsl:for-each>

       <xsl:text>&#10;</xsl:text>
	</xsl:template>
</xsl:stylesheet>

