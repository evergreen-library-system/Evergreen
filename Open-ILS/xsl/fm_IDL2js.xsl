<xsl:stylesheet
    version='1.0'
    xmlns:xsl='http://www.w3.org/1999/XSL/Transform'
    xmlns:idl="http://opensrf.org/spec/IDL/base/v1"
    xmlns:oils_persist="http://open-ils.org/spec/opensrf/IDL/persistence/v1"
    xmlns:oils_obj="http://open-ils.org/spec/opensrf/IDL/objects/v1"
    xmlns:reporter="http://open-ils.org/spec/opensrf/IDL/reporter/v1"
    xmlns:sr="http://open-ils.org/spec/opensrf/IDL/simple-reporter/v1"
    xmlns:permacrud="http://open-ils.org/spec/opensrf/IDL/permacrud/v1"
    xmlns:str="http://exslt.org/strings"
    extension-element-prefixes="str"
>
    <xsl:output method="text" />
    <xsl:strip-space elements="xsl:*"/>
    <xsl:param name="class_list"/>
 
 
    <xsl:template match="/">
var _preload_fieldmapper_IDL = {<xsl:apply-templates select="idl:IDL"/>};
for (var c in _preload_fieldmapper_IDL) {
    var x = _preload_fieldmapper_IDL[c]; x.field_map = {};
    var p = x.fields.length;
    for (var n in {isnew:1,ischanged:1,isdeleted:1}) {
        x.fields[p] = {name:n,virtual:true};
        p++;
    }
    for (var f in x.fields) x.field_map[x.fields[f].name] = x.fields[f];
}
    </xsl:template>
 
    <xsl:template match="idl:IDL">
        <xsl:choose>
            <xsl:when test="$class_list = ''">
                <xsl:for-each select="idl:class"><xsl:sort select="@id"/><xsl:apply-templates select="."/><xsl:if test="not(position() = last())">,</xsl:if></xsl:for-each>
            </xsl:when>
            <xsl:otherwise>
                <xsl:variable name="doc" select="."/>
                <xsl:for-each select="str:split($class_list,',')"><xsl:sort select="./text()"/><xsl:variable name="current_class" select="./text()"/><xsl:apply-templates select="$doc/idl:class[@id=$current_class]"/><xsl:if test="not(position() = last())">,</xsl:if></xsl:for-each>
            </xsl:otherwise>
        </xsl:choose>
    </xsl:template>
 
    <xsl:template match="idl:class">
        <xsl:value-of select="@id"/><xsl:text>:</xsl:text>
        <xsl:text>{name:"</xsl:text><xsl:value-of select="@id"/><xsl:text>",</xsl:text>
        <xsl:if test="@reporter:label">label:"<xsl:value-of select="@reporter:label"/>",</xsl:if>
        <xsl:if test="@oils_persist:restrict_primary">restrict_primary:"<xsl:value-of select="@oils_persist:restrict_primary"/>",</xsl:if>
        <xsl:if test="@oils_persist:tablename">table:"<xsl:value-of select="@oils_persist:tablename"/>",</xsl:if>
        <xsl:if test="@reporter:core = 'true'">core:true,</xsl:if><xsl:if test="@oils_persist:virtual = 'true'">virtual:true,</xsl:if>
        <xsl:if test="oils_persist:source_definition">source:"(<xsl:value-of select="oils_persist:source_definition/text()"/>)",</xsl:if>
        <xsl:if test="idl:fields/@oils_persist:primary">pkey:"<xsl:value-of select="idl:fields/@oils_persist:primary"/>",</xsl:if>
        <xsl:if test="idl:fields/@oils_persist:sequence">pkey_sequence:"<xsl:value-of select="idl:fields/@oils_persist:sequence"/>",</xsl:if>
        <xsl:if test="@oils_persist:cardinality">cardinality:"<xsl:value-of select="@oils_persist:cardinality"/>",</xsl:if>
        <xsl:apply-templates select="idl:fields"/>
        <xsl:apply-templates select="idl:field_groups"/>
    <xsl:apply-templates select="permacrud:permacrud"/>}</xsl:template>
 
    <xsl:template match="idl:fields">fields:[<xsl:for-each select="idl:field"><xsl:call-template name="printField"><xsl:with-param name='pos' select="position()"/></xsl:call-template><xsl:if test="not(position() = last())">,</xsl:if></xsl:for-each>]</xsl:template>

    <xsl:template match="idl:field_groups">
    <xsl:text>,field_groups:[</xsl:text>
      <xsl:for-each select="idl:group">
        <xsl:call-template name="printField"><xsl:with-param name='pos' select="position()"/></xsl:call-template>
        <xsl:if test="not(position() = last())">,</xsl:if>
      </xsl:for-each>
    <xsl:text>]</xsl:text></xsl:template>

    <xsl:template match="permacrud:permacrud">,permacrud:{<xsl:for-each select="permacrud:actions/*"><xsl:if test="name() = 'delete'">"</xsl:if><xsl:value-of select="name()"/><xsl:if test="name() = 'delete'">"</xsl:if>:{<xsl:call-template name='pcrudPerms'/>}<xsl:if test="not(position() = last())">,</xsl:if></xsl:for-each>}</xsl:template>
 
<!-- to simplify the logic, the first and last field are assumed to
     have values (and practically always will) -->
<xsl:template name='printField'>
  <xsl:text>{</xsl:text>
    <xsl:text>name:"</xsl:text><xsl:value-of select="@name"/><xsl:text>",</xsl:text>
    <xsl:if test="@reporter:label != ''">label:"<xsl:value-of select="@reporter:label"/>",</xsl:if>
    <xsl:if test="@oils_persist:primitive = 'true'">primitive:true,</xsl:if>
    <xsl:if test="@reporter:selector != ''">selector:"<xsl:value-of select="@reporter:selector"/>",</xsl:if>
    <xsl:if test="@sr:suggest_transform != ''">suggest_transform:"<xsl:value-of select="@sr:suggest_transform"/>",</xsl:if>
    <xsl:if test="@sr:suggest_operator != ''">suggest_operator:"<xsl:value-of select="@sr:suggest_operator"/>",</xsl:if>
    <xsl:if test="@sr:suggest_filter = 'true'">suggest_filter:true,</xsl:if>
    <xsl:if test="@sr:force_transform != ''">force_transform:[<xsl:for-each select="str:split(@sr:force_transform, ',')">"<xsl:value-of select="./text()"/>"<xsl:if test="not(position() = last())">,</xsl:if></xsl:for-each>],</xsl:if>
    <xsl:if test="@sr:force_operator != ''">force_operator:"<xsl:value-of select="@sr:force_operator"/>",</xsl:if>
    <xsl:if test="@sr:force_filter = 'true'">force_filter:true,</xsl:if>
    <xsl:if test="@sr:force_filtervalues != ''">force_filtervalues:[<xsl:for-each select="str:split(@sr:force_filtervalues, ',')">"<xsl:value-of select="./text()"/>"<xsl:if test="not(position() = last())">,</xsl:if></xsl:for-each>],</xsl:if>
    <xsl:if test="@sr:hide_from != ''">hide_from:[<xsl:for-each select="str:split(@sr:hide_from, ',')">"<xsl:value-of select="./text()"/>"<xsl:if test="not(position() = last())">,</xsl:if></xsl:for-each>],</xsl:if>
    <xsl:if test="@field_groups != ''">field_groups:[<xsl:for-each select="str:split(@field_groups, ',')">"<xsl:value-of select="./text()"/>"<xsl:if test="not(position() = last())">,</xsl:if></xsl:for-each>],</xsl:if>
    <xsl:if test="@oils_persist:virtual = 'true'">virtual:true,</xsl:if><xsl:if test="@oils_obj:required = 'true'">required:true,</xsl:if>
    <xsl:if test="@oils_persist:i18n = 'true'">i18n:true,</xsl:if><xsl:if test="@config_field = 'true'">config_field:true,</xsl:if>
    <xsl:call-template name='fieldOrLink'><xsl:with-param name='f' select="."/></xsl:call-template>
    <xsl:text>datatype:</xsl:text>
    <xsl:text>"</xsl:text><xsl:call-template name='defaultValue'><xsl:with-param name='v' select="@reporter:datatype"/><xsl:with-param name='d' select="string('text')"/></xsl:call-template><xsl:text>"</xsl:text>
  <xsl:text>}</xsl:text></xsl:template>
 
<xsl:template name="pcrudPerms">
    <xsl:if test="@permission">perms:[<xsl:for-each select="str:split(@permission,' ')">'<xsl:value-of select="./text()"/>'<xsl:if test="not(position() = last())">,</xsl:if></xsl:for-each>]</xsl:if>
</xsl:template>

<xsl:template name="fieldOrLink">
    <xsl:param name="f"/>
    <xsl:if test="$f/../../idl:links/idl:link[@field=$f/@name]">type:"link",<xsl:apply-templates select="$f/../../idl:links/idl:link[@field=$f/@name]"></xsl:apply-templates>,</xsl:if>
</xsl:template>

<xsl:template match="idl:link"><xsl:if test="@oils_persist:cardinality">cardinality:"<xsl:value-of select="@oils_persist:cardinality"/>",</xsl:if><xsl:if test="@sr:org_filter_field != ''">org_filter_field:"<xsl:value-of select="@sr:org_filter_field"/>",</xsl:if><xsl:if test="@map != ''">map:"<xsl:value-of select="@map"/>",</xsl:if>key:"<xsl:value-of select="@key"/>","class":"<xsl:value-of select="@class"/>",reltype:"<xsl:value-of select="@reltype"/>"</xsl:template>

<xsl:template name="trueFalse">
    <xsl:param name="tf"/>
    <xsl:choose>
        <xsl:when test="$tf='true'">true</xsl:when>
        <xsl:otherwise>false</xsl:otherwise>
    </xsl:choose>
</xsl:template>

<xsl:template name="defaultValue">
    <xsl:param name="v"/>
    <xsl:param name="d"/>
    <xsl:choose>
        <xsl:when test="string-length($v)=0"><xsl:value-of select="$d"/></xsl:when>
        <xsl:otherwise><xsl:value-of select="$v"/></xsl:otherwise>
    </xsl:choose>
</xsl:template>

</xsl:stylesheet>
