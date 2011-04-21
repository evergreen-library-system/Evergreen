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
      <xsl:value-of select="@prefix"/>
      <xsl:value-of select="@label"/>
      <xsl:value-of select="@suffix"/>
      <dd><xsl:apply-templates select="marc:record"/></dd>
      <dd><xsl:value-of select="act:owning_lib/@name"/></dd>
     </dl>
    </span>
   </div>
  </xsl:template>

  <xsl:template match="marc:record">
   <img>
    <xsl:attribute name="src">
      <xsl:variable name="isbnraw"><xsl:value-of select="marc:datafield[@tag='020']/marc:subfield[@code='a']"/></xsl:variable>
      <xsl:choose>
        <xsl:when test="substring-before($isbnraw,' ')">
          <xsl:variable name="isbntrimmed"><xsl:value-of select="substring-before($isbnraw,' ')"/></xsl:variable>
          <xsl:value-of select="concat('/opac/extras/ac/jacket/small/',$isbntrimmed)"/>
        </xsl:when>
        <xsl:otherwise>
          <xsl:value-of select="concat('/opac/extras/ac/jacket/small/',$isbnraw)"/>
        </xsl:otherwise>
      </xsl:choose>
    </xsl:attribute>
   </img>
   <a>
    <xsl:attribute name="href">
     <xsl:value-of select="concat('/opac/extras/unapi?format=htmlholdings-full;id=',@id)"/>
    </xsl:attribute>
    <xsl:value-of select="marc:datafield[@tag='245']/marc:subfield[@code='a']"/>
   </a>
   <xsl:text> By </xsl:text>
   <xsl:value-of select="marc:datafield[@tag='100']/marc:subfield[@code='a']"/>
   <xsl:text> / Published </xsl:text>
   <xsl:value-of select="marc:datafield[@tag='260']/marc:subfield[@code='c']|marc:datafield[@tag='261']/marc:subfield[@code='d']|marc:datafield[@tag='262']/marc:subfield[@code='d']"/>
   <span>
     <xsl:attribute name="style">
      <xsl:text>font-size:smaller;</xsl:text>
     </xsl:attribute>
     <xsl:text> (</xsl:text>
     <a>
      <xsl:attribute name="href">
       <xsl:value-of select="concat('/opac/extras/unapi?format=opac;id=',@id)"/>
      </xsl:attribute>
      <xsl:text>Dynamic Details</xsl:text>
     </a>
     <xsl:text>)</xsl:text>
   </span>
  </xsl:template>

</xsl:stylesheet>
