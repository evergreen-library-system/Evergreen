<?xml-stylesheet type="text/xsl"  href="#"?> 
<xsl:stylesheet
  xmlns:xsl="http://www.w3.org/1999/XSL/Transform"
  xmlns:res="http://example.com/test"
  version="1.0"
  >
  <xsl:template match="xsl:stylesheet">
    <html>
      <head>
        <style type="text/css">
body { background-color:#F0F0F0; font: 9pt Verdana, Arial, "Arial Unicode MS", Helvetica, sans-serif;}
input.button { font:8pt Verdana, Arail, "Arial Unicode MS", Helvetica, sans-serif;}
input.text {}
div.DDB { position:absolute; top:20pt; left:15pt; visibility:visible; }
div.DLC { position:absolute; top:20pt; left:15pt; visibility:hidden; }
div.numFound { position:absolute; top:0px; left:0pt; font-weight:bold;}

table { background-color:lightgray; font-size:10pt; margin:10pt 0pt 15pt 0pt; width:90%; border-collapse: collapse; spacing:0; padding:0;}
td { background-color:#f0f0f0; border: solid lightgray 1px; }
td.fulltag { background-color:#f0f0f0;}
td.fullind { background-color:#f0f0f0;  width:20pt;}
td.fullfield{ background-color:#f0f0f0; width:100%;}

table.signature { background-color:lightgray; font-size:10pt; margin:0; width:100%; border:none; padding:0;}
table.params { background-color:lightgray; font-size:10pt; margin:3px 0px 3px 0px; width:100%; border: solid black 1px; padding:0;}
td.params { background-color:lightgray; font-size:10pt; border: solid black 1px;}

h1 { text-decoration: underline; }

td.header { font-weight:bold; color:black; font-size:14pt; border-bottom: solid gray 2px}
td.label { vertical-align:top; padding-left:10pt; width:120pt; font-weight:normal; color:darkblue;}
td.value { vertical-align:top; text-align:left; font-weight: bold;}
span.subcode { color:darkblue;}        </style>

      </head>
      <body>
        <a name="top"/>

<!--#if expr='"$QUERY_STRING" = /limit=([^&]+)/' -->
  <!--#set var="limit" value="$1" -->
<!--#else -->
  <!--#set var="limit" value="10" -->
<!--#endif -->

<!--#if expr='"$QUERY_STRING" = /offset=([^&]+)/' -->
  <!--#set var="offset" value="$1" -->
<!--#else -->
  <!--#set var="offset" value="0" -->
<!--#endif -->

<!--#if expr='"$QUERY_STRING" = /service=([^&]+)/' -->
  <!--#set var="service" value="$1" -->
<!--#else -->
  <!--#set var="service" value="" -->
<!--#endif -->

<!--#if expr='"$QUERY_STRING" = /method=([^&]+)/' -->
  <!--#set var="method" value="$1" -->
<!--#endif -->

<!--#if expr="$QUERY_STRING = /all=on/" -->
  <!--#set var="all" value="true" -->
<!--#else -->
  <!--#set var="all" value="false" -->
<!--#endif -->

<!--#if expr="$QUERY_STRING = /param=%22([^&]+)%22/" -->
  <!--#set var="param" value="$1" -->
<!--#else -->
  <!--#set var="param" value="" -->
<!--#endif -->

        <xsl:if test="not(res:content/res:response)">
	  <br/><br/><br/><br/><br/><br/>
	  <br/><br/><br/><br/><br/><br/>
	</xsl:if>

        <form
	  method="GET"
	  action='<!--#echo var="DOCUMENT_URI" -->'
	  onsubmit='
	    this.param.value = "\"" + this.param.value + "\"";
	    if (this.all.checked) this.method.value = "opensrf.system.method.all";
	  '>
          <xsl:if test="not(res:content/res:response)">
	    <xsl:attribute name="style">
	      <xsl:value-of select="'text-align:center;'"/>
	    </xsl:attribute>
	  </xsl:if>
          Application:
	  <input name="service" type="text" value='<!--#echo var="service" -->'/>&#160;
          API Method Name Regex:
	  <input name="param" type="text" value='<!--#echo var="param" -->'>
            <xsl:if test="'<!--#echo var="all" -->' = 'true'">
	      <xsl:attribute name="disabled">
	        <xsl:value-of select="'true'"/>
	      </xsl:attribute>
	    </xsl:if>
	  </input>&#160;
	  All Methods (Use with care!)
	  <input
	    name="all"
	    type="checkbox"
	    value="on"
	    onclick='
	      if (this.checked) this.form.param.disabled = true;
	      else this.form.param.disabled = false;
	    '>
	    <xsl:if test="'<!--#echo var="all" -->' = 'true'">
	      <xsl:attribute name="checked">
	        <xsl:value-of select="'checked'"/>
	      </xsl:attribute>
	    </xsl:if>

	    </input>&#160;
          <button name="method" value="opensrf.system.method">Find 'em</button>
        </form>

        <xsl:if test="res:content/res:response">
	  <hr/>

          <xsl:apply-templates select="res:content/res:response"/>

	  <hr/>

          <form
	    method="GET"
	    action='<!--#echo var="DOCUMENT_URI" -->'
	    onsubmit='
	      this.param.value = "\"" + this.param.value + "\"";
	      if (this.all.checked) this.method.value = "opensrf.system.method.all";
	    '>
            <xsl:if test="not(res:content/res:response)">
	      <xsl:attribute name="style">
	        <xsl:value-of select="'text-align:center;'"/>
	      </xsl:attribute>
	    </xsl:if>
            Application:
	    <input name="service" type="text" value='<!--#echo var="service" -->'/>&#160;
            API Method Name Regex:
	    <input name="param" type="text" value='<!--#echo var="param" -->'>
              <xsl:if test="'<!--#echo var="all" -->' = 'true'">
	        <xsl:attribute name="disabled">
	          <xsl:value-of select="'true'"/>
	        </xsl:attribute>
	      </xsl:if>
	    </input>&#160;
	    All Methods (Use with care!)
	    <input
	      name="all"
	      type="checkbox"
	      value="on"
	      onclick='
	        if (this.checked) this.form.param.disabled = true;
	        else this.form.param.disabled = false;
	      '>
	      <xsl:if test="'<!--#echo var="all" -->' = 'true'">
	        <xsl:attribute name="checked">
	          <xsl:value-of select="'checked'"/>
	        </xsl:attribute>
	      </xsl:if>
  
	      </input>&#160;
            <button name="method" value="opensrf.system.method">Find 'em</button>
          </form>

	</xsl:if>
      </body>
    </html>
  </xsl:template>

  <xsl:template match="res:api_name">
    API Level: <xsl:value-of select="../res:api_level/text()"/> / Method: 
    <a>
      <xsl:attribute name="href">#<xsl:value-of select="./text()"/></xsl:attribute>
      <xsl:value-of select="./text()"/>
    </a>
    <br/>
  </xsl:template>

  <xsl:template match="res:response">
    <xsl:choose>
      <xsl:when test="count(//res:api_name) > 1">
        <h1>Matching Methods</h1>
        <xsl:apply-templates select="//res:api_name">
          <xsl:sort select="text()"/>
        </xsl:apply-templates>

        <h1>Method Definitions</h1>
      </xsl:when>
      <xsl:when test="count(//res:api_name) = 0">
        <h1><i>No Matching Methods Found</i></h1>
      </xsl:when>
    </xsl:choose>

    <xsl:apply-templates select="res:hash/res:pair[res:key/text()='payload']/res:value/res:array/res:datum/res:Object">
      <xsl:sort select="res:api_name/text()"/>
    </xsl:apply-templates>
  </xsl:template>


  <xsl:template match="res:Object">
    <xsl:if test="res:remote/text()='0'">

      <xsl:if test="count(//res:api_name) > 1">
        <a>
          <xsl:attribute name="name"><xsl:value-of select="res:api_name/text()"/></xsl:attribute>
        </a>
        <a href="#top">Top</a>
      </xsl:if>

      <table>
        <tr>
          <td colspan="3" class="header"><xsl:value-of select="res:api_name"/></td>
        </tr>
        <tr>
          <td class="label">API Level:</td>
          <td colspan="2" class="value"><xsl:value-of select="res:api_level"/></td>
        </tr>
        <tr>
          <td class="label">Package:</td>
          <td colspan="2" class="value"><xsl:value-of select="res:package"/></td>
        </tr>
        <tr>
          <td class="label">Required argument count:</td>
          <td colspan="2" class="value"><xsl:value-of select="res:argc"/></td>
        </tr>
        <xsl:if test="normalize-space(res:signature/res:desc/text()) != normalize-space(res:notes/text())">
          <tr>
            <td class="label">
              <xsl:attribute name='rowspan'>
                <xsl:value-of select='count(res:signature/res:params/res:hash) + 6'/>
              </xsl:attribute>
              Signature:
            </td>
          </tr>
          <xsl:apply-templates select="res:signature"/>
        </xsl:if>
        <tr>
          <td class="label">Streaming method:</td>
          <td colspan="2" class="value">
            <xsl:if test="res:stream/text()='1'">Yes</xsl:if>
            <xsl:if test="res:stream/text()='0'">No</xsl:if>
          </td>
        </tr>
        <xsl:if test="res:notes">
          <tr>
            <td class="label">Notes:</td>
            <td colspan="2" class="value"><pre style="font-weight:normal;font-size:10px;"><xsl:value-of select="res:notes"/></pre></td>
          </tr>
        </xsl:if>
      </table>
    </xsl:if>
  </xsl:template>


  <xsl:template match="res:pair">
    <tr>
      <td class="label params">
        <xsl:if test="res:key/text()='name'">Name:</xsl:if>
        <xsl:if test="res:key/text()='desc'">Description:</xsl:if>
        <xsl:if test="res:key/text()='type'">Data type:</xsl:if>
        <xsl:if test="res:key/text()='class'">Object class:</xsl:if>
      </td>
      <td class="value params"><xsl:value-of select="res:value"/></td>
    </tr>
  </xsl:template>


  <xsl:template match="res:hash">
    <tr>
      <td>
        <table class="params">
	  <tr>
	    <td class="label params">Position:</td>
	    <td class="value params"><xsl:value-of select="position()"/></td>
	  </tr>
          <xsl:apply-templates select="res:pair[res:key/text()='name']"/>
          <xsl:apply-templates select="res:pair[res:key/text()='desc']"/>
          <xsl:apply-templates select="res:pair[res:key/text()='type']"/>
          <xsl:apply-templates select="res:pair[res:key/text()='class']"/>
        </table>
      </td>
    </tr>
  </xsl:template>


  <xsl:template match="res:signature">
      <xsl:if test="res:desc">
        <tr>
          <td class="label">Description:</td>
          <td class="value"><xsl:value-of select="res:desc"/></td>
        </tr>
      </xsl:if>
      <xsl:if test="res:params/res:hash">
        <tr>
          <td class="label">
            <xsl:attribute name='rowspan'>
              <xsl:value-of select='count(res:params/res:hash) + 1'/>
            </xsl:attribute>
            Parameters:</td>
        </tr>
      </xsl:if>
      <xsl:apply-templates select="res:params/res:hash">
        <xsl:sort select="position()"/>
      </xsl:apply-templates>
      <xsl:if test="res:return">
        <tr>
          <td class="label">Returns:</td>
          <td class="value"><xsl:value-of select="res:return/res:desc"/></td>
        </tr>
        <tr>
          <td class="label">Return type:</td>
          <td class="value"><xsl:value-of select="res:return/res:type"/></td>
        </tr>
        <tr>
          <td class="label">Return type class:</td>
          <td class="value"><xsl:value-of select="res:return/res:class"/></td>
        </tr>
      </xsl:if>
  </xsl:template>


  <!--#if expr="$QUERY_STRING = /service=[^&]+/" -->
    <!--#if expr="$QUERY_STRING = /param=%22[^&]+%22/" -->
      <content xmlns="http://example.com/test">
	<!--#include virtual="/restgateway?${QUERY_STRING}"-->
        <!-- virtual='/restgateway?service=$service&method=$method&param="$param"&param=$limit&param=$offset'-->
      </content>
    <!--#endif -->
    <!--#if expr="$QUERY_STRING = /all=on/" -->
      <content xmlns="http://example.com/test">
	<!--#include virtual="/restgateway?${QUERY_STRING}"-->
        <!-- virtual='/restgateway?service=$service&method=$method&param=""&param=$limit&param=$offset' -->
      </content>
    <!--#endif -->
  <!--#endif -->


</xsl:stylesheet>
    
