<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
  
<xsl:stylesheet xmlns:xsl="http://www.w3.org/1999/XSL/Transform"
  xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
  version="1.0">
  <xsl:output method="html" doctype-public="-//W3C/DTD HTML 4.01 Transitional//EN" doctype-system="http://www.w3.org/TR/html4/strict.dtd" />    

  <xsl:template match="//FlatSearch">
    <html>
        <head>
            <meta http-equiv="Content-Type" content="text/html" charset="utf-8"/>
            <style type="text/css">
                /* This CSS controls whether data printed from an interface
                based on FlattenerGrid has visible table cell borders. */

                table { border-collapse: collapse; }
                td, th { border: 1px solid black; }
            </style>
        </head>
        <body>
            <table>
                <tbody>
                    <xsl:apply-templates select="row[@ordinal='1']"/>
                    <xsl:apply-templates select="row[not(@ordinal='1')]"/>
                </tbody>
            </table>
        </body>
    </html>
  </xsl:template>

  <xsl:template match="row[@ordinal='1']">
    <tr>
        <xsl:for-each select="column"><th><xsl:value-of select="@name"/></th></xsl:for-each>
    <tr>
    </tr>
        <xsl:for-each select="column"><td><xsl:value-of select="."/></td></xsl:for-each>
    </tr>
  </xsl:template>

   <xsl:template match="row">
    <tr>
        <xsl:for-each select="column"><td><xsl:value-of select="."/></td></xsl:for-each>
    </tr>
  </xsl:template>
    
</xsl:stylesheet>
