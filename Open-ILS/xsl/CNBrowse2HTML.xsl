<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
  
<xsl:stylesheet xmlns:xsl="http://www.w3.org/1999/XSL/Transform"
  xmlns="http://www.w3.org/1999/xhtml"
  xmlns:xhtml="http://www.w3.org/1999/xhtml"
  xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
  xmlns:marc="http://www.loc.gov/MARC21/slim"
  xmlns:hold="http://open-ils.org/spec/holdings/v1"
  xmlns:act='http://open-ils.org/spec/actors/v1'
  version="1.0">
  <xsl:output method="html" doctype-public="-//W3C/DTD HTML 4.01 Transitional//EN" doctype-system="http://www.w3.org/TR/html4/strict.dtd" />    
  <xsl:template match="/">
     <html>
       <head>
         <meta http-equiv="Content-Type" content="text/html" charset="utf-8"/>
       </head>
       <body>
        <span>
	 <a>
	  <xsl:attribute name="href">
	   <xsl:value-of select="$prev"/>
	  </xsl:attribute>
	  <xsl:text>Previous</xsl:text>
	 </a>
	 <xsl:text> -- </xsl:text>
	 <a>
	  <xsl:attribute name="href">
	   <xsl:value-of select="$next"/>
	  </xsl:attribute>
	  <xsl:text>Next</xsl:text>
	 </a>
	</span>
	<hr/>
        <xsl:apply-templates select="//hold:volume"/>
	<hr/>
        <span>
	 <a>
	  <xsl:attribute name="href">
	   <xsl:value-of select="$prev"/>
	  </xsl:attribute>
	  <xsl:text>Previous</xsl:text>
	 </a>
	 <xsl:text> -- </xsl:text>
	 <a>
	  <xsl:attribute name="href">
	   <xsl:value-of select="$next"/>
	  </xsl:attribute>
	  <xsl:text>Next</xsl:text>
	 </a>
	</span>
       </body>
     </html>
  </xsl:template>

  <xsl:template match="hold:volume">
   <div style="border:solid #999999 1px;">
    <span>
     <dl>
      <xsl:value-of select="@label"/>
      <dd><xsl:apply-templates select="marc:record"/></dd>
      <dd><xsl:value-of select="act:owning_lib/@name"/></dd>
     </dl>
    </span>
   </div>
  </xsl:template>

  <xsl:template match="marc:record">
   <a>
    <xsl:attribute name="href">
     <xsl:value-of select="concat('/opac/extras/unapi?format=htmlholdings-full;id=',@id)"/>
    </xsl:attribute>
    <xsl:value-of select="marc:datafield[@tag='245']/marc:subfield[@code='a']"/>
   </a>
   <xsl:text> By </xsl:text>
   <xsl:value-of select="marc:datafield[@tag='100']/marc:subfield[@code='a']"/>
  </xsl:template>

</xsl:stylesheet>
