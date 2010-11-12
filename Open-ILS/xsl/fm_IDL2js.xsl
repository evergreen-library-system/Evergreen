<xsl:stylesheet
    version='1.0'
    xmlns:xsl='http://www.w3.org/1999/XSL/Transform'
    xmlns:idl="http://opensrf.org/spec/IDL/base/v1"
    xmlns:oils_persist="http://open-ils.org/spec/opensrf/IDL/persistence/v1"
    xmlns:oils_obj="http://open-ils.org/spec/opensrf/IDL/objects/v1"
    xmlns:reporter="http://open-ils.org/spec/opensrf/IDL/reporter/v1"
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
    for (var n in {isnew:1,ischanged:1,isdeleted:1}) x.fields[p] = {name:n,type:'field',virtual:true,array_position:p++};
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
 
    <xsl:template match="idl:class"><xsl:value-of select="@id"/>:{name:"<xsl:value-of select="@id"/>",label:"<xsl:call-template name='defaultValue'><xsl:with-param name='v' select="@reporter:label"/><xsl:with-param name='d' select="@id"/></xsl:call-template>",restrict_primary:"<xsl:value-of select="@oils_persist:restrict_primary"/>",virtual:<xsl:call-template name='trueFalse'><xsl:with-param name='tf' select="@oils_persist:virtual"/></xsl:call-template>,pkey:"<xsl:value-of select="idl:fields/@oils_persist:primary"/>",pkey_sequence:"<xsl:value-of select="idl:fields/@oils_persist:sequence"/>",<xsl:apply-templates select="idl:fields"/><xsl:apply-templates select="permacrud:permacrud"/>}</xsl:template>
 
    <xsl:template match="idl:fields">fields:[<xsl:for-each select="idl:field"><xsl:call-template name="printField"><xsl:with-param name='pos' select="position()"/></xsl:call-template><xsl:if test="not(position() = last())">,</xsl:if></xsl:for-each>]</xsl:template>

    <xsl:template match="permacrud:permacrud">,permacrud:{<xsl:for-each select="permacrud:actions/*"><xsl:if test="name() = 'delete'">"</xsl:if><xsl:value-of select="name()"/><xsl:if test="name() = 'delete'">"</xsl:if>:{<xsl:call-template name='pcrudPerms'/>}<xsl:if test="not(position() = last())">,</xsl:if></xsl:for-each>}</xsl:template>
 
<xsl:template name='printField'><xsl:param name="pos"/>{name:"<xsl:value-of select="@name"/>",label:"<xsl:call-template name='defaultValue'><xsl:with-param name='v' select="@reporter:label"/><xsl:with-param name='d' select="@name"/></xsl:call-template>",datatype:"<xsl:call-template name='defaultValue'><xsl:with-param name='v' select="@reporter:datatype"/><xsl:with-param name='d' select="string('text')"/></xsl:call-template>",primitive:"<xsl:value-of select="@oils_persist:primitive"/>",selector:"<xsl:value-of select="@reporter:selector"/>",array_position:"<xsl:value-of select="$pos - 1"/>",<xsl:call-template name='fieldOrLink'><xsl:with-param name='f' select="."/></xsl:call-template>,virtual:<xsl:call-template name='trueFalse'><xsl:with-param name='tf' select="@oils_persist:virtual"/></xsl:call-template>,required:<xsl:call-template name='trueFalse'><xsl:with-param name='tf' select="@oils_obj:required"/></xsl:call-template>,i18n:<xsl:call-template name='trueFalse'><xsl:with-param name='tf' select="@oils_persist:i18n"/></xsl:call-template>}</xsl:template>
 
<xsl:template name="pcrudPerms">
    <xsl:if test="@permission">perms:[<xsl:for-each select="str:split(@permission,' ')">'<xsl:value-of select="./text()"/>'<xsl:if test="not(position() = last())">,</xsl:if></xsl:for-each>]</xsl:if>
</xsl:template>

<xsl:template name="fieldOrLink">
    <xsl:param name="f"/>
    <xsl:choose>
        <xsl:when test="$f/../../idl:links/idl:link[@field=$f/@name]">type:"link",<xsl:apply-templates select="$f/../../idl:links/idl:link[@field=$f/@name]"></xsl:apply-templates></xsl:when>
        <xsl:otherwise>type:"field"</xsl:otherwise>
    </xsl:choose>
</xsl:template>

<xsl:template match="idl:link">key:"<xsl:value-of select="@key"/>","class":"<xsl:value-of select="@class"/>",reltype:"<xsl:value-of select="@reltype"/>"</xsl:template>

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
