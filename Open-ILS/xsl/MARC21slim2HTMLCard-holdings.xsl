<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
  
<xsl:stylesheet xmlns:xsl="http://www.w3.org/1999/XSL/Transform"
  xmlns="http://www.w3.org/1999/xhtml"
  xmlns:xhtml="http://www.w3.org/1999/xhtml"
  xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
  xmlns:marc="http://www.loc.gov/MARC21/slim"
  xmlns:hold="http://open-ils.org/spec/holdings/v1"
  version="1.0">
  <xsl:output method="html" doctype-public="-//W3C/DTD HTML 4.01 Transitional//EN" doctype-system="http://www.w3.org/TR/html4/strict.dtd" />    
  <xsl:template match="/">
     <html>
       <head>
         <meta http-equiv="Content-Type" content="text/html" charset="utf-8"/>
         <link href="{$base_dir}/htmlcard.css" rel="stylesheet" type="text/css" />
      	 <xsl:apply-templates select="/marc:collection/xhtml:link"/>
       </head>
       <body>
        <xsl:apply-templates select="//marc:record"/>
       </body>
     </html>
  </xsl:template>
      
  <xsl:template match="marc:record">
    <div class="cardimage">
     <xsl:apply-templates select="marc:datafield[@tag!='082' and @tag!='092' and @tag!='010']"/>
     <span class="bottom">
      <xsl:apply-templates select="xhtml:link[@rel='otherFormat' and contains(@href,'format=')]"/>
      <xsl:apply-templates select="xhtml:abbr[@class='unapi-id']"/>
      <xsl:apply-templates select="marc:controlfield[@tag='001']"/>
      <xsl:apply-templates select="marc:datafield[@tag='082' or @tag='092' or @tag='010']"/>
     </span>
    </div>
    <br/>
    <xsl:apply-templates select="hold:volumes"/>
    <br/>
  </xsl:template>

  <xsl:template match="xhtml:abbr">
    <abbr>
      <xsl:attribute name="title">
        <xsl:value-of select="@title"/>
      </xsl:attribute>
      <xsl:attribute name="class">
        <xsl:value-of select="@class"/>
      </xsl:attribute>
      <xsl:value-of select="."/>
    </abbr>
  </xsl:template>

  <xsl:template match="xhtml:link">
    <xsl:choose>
      <xsl:when test="@title='unapi'">
        <link>
          <xsl:attribute name="title">
            <xsl:value-of select="@title"/>
          </xsl:attribute>
          <xsl:attribute name="rel">
            <xsl:value-of select="@rel"/>
          </xsl:attribute>
          <xsl:attribute name="href">
            <xsl:value-of select="@href"/>
          </xsl:attribute>
          <xsl:value-of select="."/>
        </link>
      </xsl:when>
      <xsl:when test="@rel='otherFormat' and contains(@href,'format=')">
        <a>
          <xsl:attribute name="href">
            <xsl:value-of select="@href"/>
          </xsl:attribute>
          <xsl:value-of select="@title"/>
        </a>
        <br/>
      </xsl:when>
    </xsl:choose>
  </xsl:template>

  <xsl:template match="hold:volumes">
    <xsl:if test="count(hold:volume/hold:copies/hold:copy) &gt; 0">
    	<u>Holdings</u>
    </xsl:if>
    <ul>
    <xsl:apply-templates select="hold:volume">
      <xsl:sort select="@lib"/>
    </xsl:apply-templates>
    </ul>
  </xsl:template>

  <xsl:template match="hold:volume">
      <li> <b><xsl:value-of select="./@label"/></b>
        <xsl:apply-templates select="hold:copies"/>
      </li>
  </xsl:template>

  <xsl:template match="hold:copies">
    <ul>
    <xsl:apply-templates select="hold:copy">
      <xsl:sort select="hold:location"/>
    </xsl:apply-templates>
    </ul>
  </xsl:template>

  <xsl:template match="hold:copy">
      <li> <xsl:value-of select="@barcode"/>
        <ul>
	  <li>Circulating from <b><xsl:value-of select="hold:circlib"/></b></li>
	  <li>Located at <b><xsl:value-of select="hold:location"/></b></li>
	  <li>Status is <b><xsl:value-of select="hold:status"/></b></li>
	  <xsl:apply-templates select="hold:statcats"/>
	</ul>
      </li>
  </xsl:template>

  <xsl:template match="hold:statcats">
    <xsl:if test="count(hold:statcat) &gt; 0">
      <li>Statistical Catagories
        <ul>
        <xsl:apply-templates select="hold:statcat">
          <xsl:sort select="@name"/>
        </xsl:apply-templates>
        </ul>
      </li>
    </xsl:if>
  </xsl:template>

  <xsl:template match="hold:statcat">
      <li> <b><xsl:value-of select="@name"/></b>: <xsl:value-of select="."/> </li>
  </xsl:template>

  <xsl:template match="marc:controlfield">
      <span class="oclc">#<xsl:value-of select="substring(.,4)"/></span>
  </xsl:template>
      
  <xsl:template match="marc:datafield">
    <xsl:if test="starts-with(@tag, '1')">
      <p class="mainheading"><xsl:value-of select="."/></p>
    </xsl:if>

    <xsl:if test="starts-with(@tag, '24') and /marc:record/marc:datafield[@tag='100']">
      <span class="title"><xsl:value-of select="."/></span>
    </xsl:if>

    <xsl:if test="starts-with(@tag, '24') and not(/marc:record/marc:datafield[@tag='100'])">
      <span class="titlemain"><xsl:value-of select="."/></span><br/>
    </xsl:if>

    <xsl:if test="@tag='260'">
      <xsl:value-of select="."/>
    </xsl:if>

    <xsl:if test="@tag='300'">
      <p class="extent"><xsl:value-of select="."/></p>
     </xsl:if>

    <xsl:if test="starts-with(@tag, '5')">
      <p class="note"><xsl:value-of select="."/></p>
    </xsl:if>

    <xsl:if test="@tag='650'">
      <span class='counter'><xsl:number count="marc:datafield[@tag='650']"/>.</span> <xsl:apply-templates select="marc:subfield"/>
    </xsl:if>

    <xsl:if test="@tag='653'">
      <span class="counter"><xsl:number format="i" count="marc:datafield[@tag='653']"/>.</span> <xsl:apply-templates select="marc:subfield"/>
    </xsl:if>

    <xsl:if test="@tag='010'">
      <xsl:variable name="LCCN.nospace" select="translate(., ' ', '')"/>
      <xsl:variable name="LCCN.length" select="string-length($LCCN.nospace)"/>
      <xsl:variable name="LCCN.display" select="concat(substring($LCCN.nospace, 1, $LCCN.length - 6), '-', format-number(substring($LCCN.nospace, $LCCN.length - 5),'#'))"/>
      <span class="LCCN">LCCN:<xsl:value-of select="$LCCN.display"/></span>
    </xsl:if>

    <xsl:if test="@tag='082' or @tag='092'">
      <span class="DDC"><xsl:value-of select="marc:subfield[@code='a']"/></span>
    </xsl:if>

    <xsl:if test="@tag='856'">
     <br/><xsl:apply-templates mode="link" select="marc:subfield" />
    </xsl:if>
  </xsl:template>

  <xsl:template match="marc:subfield" mode="link">
    <xsl:if test="@code='u'">
      <span class="link">
        <a class="url" href="{.}">
                <xsl:choose>
                        <xsl:when test="../marc:subfield[@code='y']">
                                <xsl:value-of select="../marc:subfield[@code='y']"/>
                        </xsl:when>
                        <xsl:when test="../marc:subfield[@code='3']">
                                <xsl:value-of select="../marc:subfield[@code='3']"/>
                        </xsl:when>
                        <xsl:otherwise>
                                <xsl:value-of select="."/>
                        </xsl:otherwise>
                </xsl:choose>
        </a>
      </span>
    </xsl:if>
  </xsl:template>
  
  <xsl:template match="marc:subfield">
    <xsl:if test="@code!='2'">    
     <xsl:if test="@code!='a'">--</xsl:if>
     <xsl:value-of select="."/>
    </xsl:if>
  </xsl:template>

</xsl:stylesheet>
