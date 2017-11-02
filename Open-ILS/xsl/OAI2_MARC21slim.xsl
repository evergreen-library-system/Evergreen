<xsl:stylesheet version="1.0"
                xmlns:xsl="http://www.w3.org/1999/XSL/Transform"
                xmlns:marc="http://www.loc.gov/MARC21/slim">
    <xsl:output omit-xml-declaration="yes"/>

    <xsl:template match="node()|@*">
        <xsl:copy>
            <xsl:apply-templates select="node()|@*"/>
        </xsl:copy>
    </xsl:template>

    <xsl:template match="*">
        <xsl:element name="marc:{name()}" namespace="http://www.loc.gov/MARC21/slim">
            <xsl:copy-of select="namespace::*"/>
            <xsl:apply-templates select="node()|@*"/>
        </xsl:element>
    </xsl:template>
</xsl:stylesheet>