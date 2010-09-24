<?xml version='1.0'?>
<xsl:stylesheet  
    xmlns:xsl="http://www.w3.org/1999/XSL/Transform" version="1.0">

<xsl:import href="docbook-xsl/fo/docbook.xsl"/>  

<!-- main pdf stylesheet -->
<!--<xsl:import href="evergreen_titlepage.templates.xsl"/>--> <!-- custom title font sizes and layout -->
<xsl:import href="evergreen_titlepage.xsl"/> <!-- hide revisions and set section.title.levelx.properties -->


<xsl:import href="evergreen_pagesetup.xsl"/> <!-- custom header/footer -->
<xsl:import href="docbook-xsl/fo/evergreen_inline.xsl"/> <!-- custom inline styles (italics for giumenu, etc), must be in /fo/ to work -->
<xsl:import href="evergreen_fo_graphics.xsl"/>  <!-- customized graphics.xsl, scales pdf images to 75% unless scale="x" or scalefit="1" -->

<xsl:param name="page.margin.inner" select="'0.75in'"/>
<xsl:param name="page.margin.outer" select="'0.75in'"/>
<xsl:param name="page.margin.top" select="'0.2in'"/>
<xsl:param name="keep.relative.image.uris" select="0"/>
<xsl:param name="admon.graphics" select="1"/> <!-- adds image for note, tip, and caution -->
<xsl:param name="admon.textlabel" select="0"/> <!-- removes title of note, tip, and caution -->
<xsl:param name="admon.graphics.path" select="'media/'"/>
<xsl:param name="use.role.for.media.object" select="1"/>
<xsl:param name="ulink.show" select="0"/>
<xsl:param name="fop1.extensions" select="1" />
<xsl:param name="callout.graphics" select="1" />
<xsl:param name="callout.graphics.extension" select="'.png'" />
<xsl:param name="callout.graphics.path" select="'../media/'" />
<xsl:param name="tablecolumns.extension" select="0" />
<xsl:param name="menuchoice.menu.separator"> &#x2192; </xsl:param>

<xsl:param name="header.rule" select="0"/> <!-- remove header horizontal rule -->
<xsl:param name="body.start.indent" select="'0pt'"/> <!-- reduce left-indent to provide more content space -->
<xsl:param name="body.font.master" select="'11'"/>
<xsl:param name="glossary.sort" select="1"/> <!-- sort glossterms aphabetically regardless of order in xml docs -->
<xsl:param name="glossterm.separation" select="'0.1in'"/> <!-- vertical space between term and definition paragraph -->
<xsl:param name="hyphenate">false</xsl:param> <!-- hyphenation pattern not installed yet, turn off to avoid output error -->
<xsl:param name="body.font.family">serif</xsl:param>
<xsl:param name="dingbat.font.family">serif</xsl:param>
<!--<xsl:param name="symbol.font.family">Symbol,ZapfDingbats</xsl:param>-->
<xsl:param name="footer.column.widths">8 1 1</xsl:param> <!-- set relative width of footer columns, leaving plenty of room for chapter titles -->
  
  <!-- set some footer properties -->
<xsl:attribute-set name="footer.content.properties">
  <xsl:attribute name="font-family">serif</xsl:attribute>
  <xsl:attribute name="font-size">9pt</xsl:attribute>
  <xsl:attribute name="padding-top">5pt</xsl:attribute>
</xsl:attribute-set>


<!-- define empty header.content template to override default template from fo/pagesetup.xsl with no header -->
<xsl:template name="header.content">
</xsl:template>

<!-- keep step text and images together, not split by page breaks -->
  <xsl:attribute-set name="informal.object.properties">
  <xsl:attribute name="keep-together.within-column">always</xsl:attribute>
</xsl:attribute-set>

<!-- set link color/style in pdf cross references -->
<xsl:attribute-set name="xref.properties">
  <xsl:attribute name="color">#304F14</xsl:attribute>
  <xsl:attribute name="text-decoration">underline</xsl:attribute>  
</xsl:attribute-set>
  
 
<!-- set link color/style for link tag --> 
  <xsl:attribute-set name="link.properties">
    <xsl:attribute name="color">#304F14</xsl:attribute>
    <xsl:attribute name="text-decoration">underline</xsl:attribute>    
  </xsl:attribute-set>
  
<!-- formatting of admonitions - note, caution, tip -->
  <xsl:attribute-set name="graphical.admonition.properties">
    <xsl:attribute name="font-size">10pt</xsl:attribute>   
    <xsl:attribute name="border">0.5pt solid #304F14</xsl:attribute> 
    <xsl:attribute name="padding">1pt</xsl:attribute>
  </xsl:attribute-set>
  
  <xsl:attribute-set name="admonition.properties">
    <xsl:attribute name="margin-right">0.1in</xsl:attribute>
    <xsl:attribute name="margin-top">0.1in</xsl:attribute>
    <xsl:attribute name="margin-bottom">0.1in</xsl:attribute>
  </xsl:attribute-set>

 
 <!-- format pdf table of contents -->
  <xsl:attribute-set name="toc.line.properties">
    <xsl:attribute name="color">#304F14</xsl:attribute>
    <xsl:attribute name="font-size">10pt</xsl:attribute> 
    <xsl:attribute name="font-family">serif</xsl:attribute>
    <xsl:attribute name="text-decoration">underline</xsl:attribute>  
  </xsl:attribute-set>
  
<!-- properties for informal tables, especially to allow breaking across pages -->
  
  <xsl:attribute-set name="informaltable.properties">
    <xsl:attribute name="font-size">10pt</xsl:attribute>
<xsl:attribute name="width">100%</xsl:attribute>    
    <xsl:attribute name="keep-together.within-column">auto</xsl:attribute>
  </xsl:attribute-set>
 
 <xsl:attribute-set name="table.properties">
<xsl:attribute name="width">100%</xsl:attribute>    
    <xsl:attribute name="keep-together.within-column">auto</xsl:attribute>
  </xsl:attribute-set>

<xsl:attribute-set name="monospace.verbatim.properties">
<!--<xsl:attribute name="font-family">Lucida Sans Typewriter</xsl:attribute>-->
  <xsl:attribute name="font-size">8pt</xsl:attribute>
  <xsl:attribute name="keep-together.within-column">always</xsl:attribute>
</xsl:attribute-set>


</xsl:stylesheet>
