<?xml-stylesheet type="text/xsl"  href="#"?> 
<xsl:stylesheet
  xmlns:xsl="http://www.w3.org/1999/XSL/Transform"
  xmlns:res="http://opensrf.org/-/namespaces/gateway/v1"
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

<!--#if expr='$QUERY_STRING = /limit=([^&]+)/' -->
  <!--#set var="limit" value="$1" -->
<!--#else -->
  <!--#set var="limit" value="25" -->
<!--#endif -->

<!--#if expr='$QUERY_STRING = /offset=([^&]+)/' -->
  <!--#set var="offset" value="$1" -->
<!--#else -->
  <!--#set var="offset" value="0" -->
<!--#endif -->

<!--#if expr='$QUERY_STRING = /service=([^&]+)/' -->
  <!--#set var="service" value="$1" -->
<!--#else -->
  <!--#set var="service" value="" -->
<!--#endif -->

<!--#if expr='$QUERY_STRING = /method=([^&]+)/' -->
  <!--#set var="method" value="$1" -->
<!--#endif -->

<!--#if expr="$QUERY_STRING = /all=on/" -->
  <!--#set var="all" value="on" -->
  <!--#set var="method" value="opensrf.sysemt.method.all" -->
<!--#else -->
  <!--#set var="all" value="off" -->
  <!--#set var="method" value="opensrf.sysemt.method" -->
<!--#endif -->

<!--#if expr='$QUERY_STRING = /param=%22(.+?)%22/' -->
  <!--#set var="param" value="$1" -->
<!--#else -->
  <!--#set var="param" value="" -->
<!--#endif -->

        <xsl:if test="not(res:response)">
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
          <xsl:if test="not(res:response)">
	    <xsl:attribute name="style">
	      <xsl:value-of select="'text-align:center;'"/>
	    </xsl:attribute>
	  </xsl:if>
          Application:
	  <input name="service" type="text" value='<!--#echo var="service" -->'/>&#160;
          API Method Name Regex:
	  <input name="param" type="text" value='<!--#echo var="param" -->'>
            <xsl:if test="'<!--#echo var="all" -->' = 'on'">
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
	    <xsl:if test="'<!--#echo var="all" -->' = 'on'">
	      <xsl:attribute name="checked">
	        <xsl:value-of select="'checked'"/>
	      </xsl:attribute>
	    </xsl:if>

	    </input>&#160;
          <input type="hidden" name="offset" value="<!--#echo var="offset" -->"/>
          <button name="limit" value="<!--#echo var="limit" -->">Find 'em</button>
        </form>

        <xsl:if test="res:response">
	  <hr/>

          <xsl:apply-templates select="res:response"/>

	  <hr/>

          <form
	    method="GET"
	    action='<!--#echo var="DOCUMENT_URI" -->'
	    onsubmit='
	      this.param.value = "\"" + this.param.value + "\"";
	      if (this.all.checked) this.method.value = "opensrf.system.method.all";
	    '>
            <xsl:if test="not(res:response)">
	      <xsl:attribute name="style">
	        <xsl:value-of select="'text-align:center;'"/>
	      </xsl:attribute>
	    </xsl:if>
            Application:
	    <input name="service" type="text" value='<!--#echo var="service" -->'/>&#160;
            API Method Name Regex:
	    <input name="param" type="text" value='<!--#echo var="param" -->'>
              <xsl:if test="'<!--#echo var="all" -->' = 'on'">
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
	      <xsl:if test="'<!--#echo var="all" -->' = 'on'">
	        <xsl:attribute name="checked">
	          <xsl:value-of select="'checked'"/>
	        </xsl:attribute>
	      </xsl:if>
  
	      </input>&#160;
            <input type="hidden" name="offset" value="<!--#echo var="offset" -->"/>
            <button name="limit" value="<!--#echo var="limit" -->">Find 'em</button>
          </form>

	</xsl:if>
      </body>
    </html>
  </xsl:template>

  <xsl:template name="apiNameLink">
    API Level: <xsl:value-of select="../res:element[@key='api_level']/res:number"/> / Method: 
    <a>
      <xsl:attribute name="href">#<xsl:value-of select="../res:element[@key='api_level']/res:number"/>/<xsl:value-of select="res:string"/></xsl:attribute>
      <xsl:value-of select="res:string"/>
    </a>
    <br/>
  </xsl:template>

  <xsl:template match="res:response">
    <xsl:choose>
      <xsl:when test="count(//res:element[@key='api_name']) > 1 or <!--#echo var="offset" --> > 0">
        <h1>Matching Methods</h1>

	<xsl:if test="<!--#echo var="offset" --> &gt; 0">
	  <span>
	    <a>
              <xsl:attribute name="href">docgen.xsl?service=<!--#echo var="service" -->&amp;all=<!--#echo var="all" -->&amp;param="<!--#echo var="param" -->"&amp;limit=<!--#echo var="limit" -->&amp;offset=<xsl:value-of select='<!--#echo var="offset" --> - <!--#echo var="limit" -->'/></xsl:attribute>
		Previous Page</a>
	    //
	  </span>
	</xsl:if>


        <span>
	  <xsl:value-of select='<!--#echo var="offset" --> + 1'/>
	    -
	  <xsl:value-of select='<!--#echo var="offset" --> + count(//res:element[@key="api_name"])'/>
	</span>

	<xsl:if test="count(//res:element[@key='api_name']) = <!--#echo var="limit" -->">
	  <span>
	    //
	    <a>
              <xsl:attribute name="href">docgen.xsl?service=<!--#echo var="service" -->&amp;all=<!--#echo var="all" -->&amp;param="<!--#echo var="param" -->"&amp;limit=<!--#echo var="limit" -->&amp;offset=<xsl:value-of select='<!--#echo var="offset" --> + <!--#echo var="limit" -->'/></xsl:attribute>
		Next Page</a>
	  </span>
	</xsl:if>

        <br/>
        <br/>

	<xsl:for-each select="//res:element[@key='api_name']">
          <xsl:sort select="concat(../res:element[@key='api_level']/res:number/text(), res:string/text())"/>
          <xsl:call-template name="apiNameLink"/>
        </xsl:for-each>

        <h1>Method Definitions</h1>
      </xsl:when>
      <xsl:when test="count(//res:element[@key='api_name']) = 0">
        <h1><i>No Matching Methods Found</i></h1>
      </xsl:when>
    </xsl:choose>

    <xsl:for-each select="res:payload/res:object">
      <xsl:sort select="concat(../res:element[@key='api_level']/res:number/text(), res:string/text())"/>
      <xsl:call-template name="methodDefinition"/>
    </xsl:for-each>
  </xsl:template>


  <xsl:template name="methodDefinition">
    <xsl:if test="res:element[@key='remote']/res:number/text()='0'">

      <xsl:if test="count(//res:element[@key='api_name']) > 1">
        <a>
          <xsl:attribute name="name"><xsl:value-of select="res:element[@key='api_level']/res:number"/>/<xsl:value-of select="res:element[@key='api_name']/res:string"/></xsl:attribute>
        </a>
        <a href="#top">Top</a>
      </xsl:if>

      <table>
        <tr>
          <td colspan="3" class="header"><xsl:value-of select="res:element[@key='api_name']/res:string"/></td>
        </tr>
        <tr>
          <td class="label">API Level:</td>
          <td colspan="2" class="value"><xsl:value-of select="res:element[@key='api_level']/res:number"/></td>
        </tr>
        <tr>
          <td class="label">Package:</td>
          <td colspan="2" class="value"><xsl:value-of select="res:element[@key='package']/res:string"/></td>
        </tr>
        <tr>
          <td class="label">Packaged Method:</td>
          <td colspan="2" class="value"><xsl:value-of select="res:element[@key='method']/res:string"/></td>
        </tr>
        <tr>
          <td class="label">Required argument count:</td>
          <td colspan="2" class="value"><xsl:value-of select="res:element[@key='argc']/res:number"/></td>
        </tr>
        <xsl:if test="normalize-space(res:element[@key='signature']/res:object/res:element[@key='desc']/res:string/text()) != normalize-space(res:element[@key='notes']/res:string/text())">
          <tr>
            <td class="label">
              <xsl:attribute name='rowspan'>
                <xsl:value-of select='
		  count(res:element[@key="signature"]/res:object/res:element[@key="params"]/res:array/res:object) +
		  count(res:element[@key="signature"]/res:object/res:element[@key="params"]/res:array[res:object]) +
		  5
		'/>
              </xsl:attribute>
              Signature:
            </td>
          </tr>
	  <xsl:for-each select="res:element[@key='signature']/res:object">
            <xsl:call-template name="methodSignature"/>
	  </xsl:for-each>
        </xsl:if>
        <tr>
          <td class="label">Streaming method:</td>
          <td colspan="2" class="value">
            <xsl:if test="res:element[@key='stream']/res:number/text()='1'">Yes</xsl:if>
            <xsl:if test="res:element[@key='stream']/res:number/text()='0'">No</xsl:if>
          </td>
        </tr>
        <xsl:if test="res:element[@key='notes']">
          <tr>
            <td class="label">Notes:</td>
            <td colspan="2" class="value"><pre style="font-weight:normal;font-size:10px;"><xsl:value-of select="res:element[@key='notes']/res:string"/></pre></td>
          </tr>
        </xsl:if>
      </table>
    </xsl:if>
  </xsl:template>


  <xsl:template name="paramInfoLine">
    <tr>
      <td class="label params">
        <xsl:if test="@key='name'">Name:</xsl:if>
        <xsl:if test="@key='desc'">Description:</xsl:if>
        <xsl:if test="@key='type'">Data type:</xsl:if>
        <xsl:if test="@key='class'">Object class:</xsl:if>
      </td>
      <td class="value params"><xsl:value-of select="res:string"/></td>
    </tr>
  </xsl:template>


  <xsl:template name="paramInfo">
    <tr>
      <td>
        <table class="params">
	  <tr>
	    <td class="label params">Position:</td>
	    <td class="value params"><xsl:value-of select="position()"/></td>
	  </tr>
	  <xsl:for-each select="res:element">
          	<xsl:call-template name="paramInfoLine"/>
	  </xsl:for-each>
        </table>
      </td>
    </tr>
  </xsl:template>


  <xsl:template name="methodSignature">
      <xsl:if test="res:element[@key='desc']">
        <tr>
          <td class="label">Description:</td>
          <td class="value"><xsl:value-of select="res:element[@key='desc']/res:string"/></td>
        </tr>
      </xsl:if>
      <xsl:if test="res:element[@key='params']/res:array/res:object">
        <tr>
          <td class="label">
            <xsl:attribute name='rowspan'>
              <xsl:value-of select='count(res:element[@key="params"]/res:array/res:object) + 1'/>
            </xsl:attribute>
            Parameters:</td>
        </tr>
      </xsl:if>
      <xsl:for-each select="res:element[@key='params']/res:array/res:object">
        <xsl:sort select="position()"/>
        <xsl:call-template name="paramInfo"/>
      </xsl:for-each>
      <xsl:if test="res:element[@key='return']">
        <tr>
          <td class="label">Returns:</td>
          <td class="value"><xsl:value-of select="res:element[@key='return']/res:object/res:element[@key='desc']/res:string"/></td>
        </tr>
        <tr>
          <td class="label">Return type:</td>
          <td class="value"><xsl:value-of select="res:element[@key='return']/res:object/res:element[@key='type']/res:string"/></td>
        </tr>
        <tr>
          <td class="label">Return type class:</td>
          <td class="value"><xsl:value-of select="res:element[@key='return']/res:object/res:element[@key='class']/res:string"/></td>
        </tr>
      </xsl:if>
  </xsl:template>


  <!--#if expr="$QUERY_STRING = /service=[^&]+/" -->
    <!--#if expr="$QUERY_STRING = /param=%22[^&]+%22/" -->
      <!-- virtual="/gateway?format=xml&${QUERY_STRING}"-->
      <!-- virtual="/restgateway?${QUERY_STRING}"-->
      <!--#include virtual='/gateway?format=xml&service=$service&method=opensrf.system.method&param="$param"&param=$limit&param=$offset'-->
    <!--#endif -->
    <!--#if expr="$QUERY_STRING = /all=on/" -->
      <!-- virtual="/gateway?format=xml&${QUERY_STRING}"-->
      <!-- virtual="/restgateway?${QUERY_STRING}"-->
      <!--#include virtual='/gateway?format=xml&service=$service&method=opensrf.system.method.all&param=$limit&param=$offset' -->
    <!--#endif -->
  <!--#endif -->


</xsl:stylesheet>

