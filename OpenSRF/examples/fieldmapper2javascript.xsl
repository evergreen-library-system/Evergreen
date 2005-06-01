<xsl:stylesheet
	version='1.0'
	xmlns:xsl='http://www.w3.org/1999/XSL/Transform'
	xmlns:opensrf="http://opensrf.org/xmlns/opensrf"
	xmlns:cdbi="http://opensrf.org/xmlns/opensrf/cdbi"
	xmlns:perl="http://opensrf.org/xmlns/opensrf/perl"
	xmlns:javascript="http://opensrf.org/xmlns/opensrf/javascript"
	xmlns:c="http://opensrf.org/xmlns/opensrf/c">
	<xsl:output method="text" />
	<xsl:strip-space elements="xsl:*"/>
	<xsl:variable name="last_field_pos"/>

	<xsl:template match="/">
// support functions
 
var IE = false;
var unit_test = false;
 
function instanceOf(object, constructorFunction) {
	if(!IE) {
		while (object != null) {
			if (object == constructorFunction.prototype)
				return true;
			object = object.__proto__;
		}
	} else {
		while(object != null) {
			if( object instanceof constructorFunction )
				return true;
			object = object.__proto__;
		}
	}
	return false;
}
 
// Top level superclass
function Fieldmapper(array) {
        this.array = [];
        if(array) {
                if (array.constructor == Array) {
                        this.array = array;
                } else if ( instanceOf( array, String ) || instanceOf( array, Number ) ) {

                        var obj = null;
                        if (this.cacheable) {
                                try {
                                        obj = this.baseClass.obj_cache[this.classname][array];
                                } catch (E) {};
                        }

                        if (!obj) {
                                obj = user_request(
                                        'open-ils.proxy',
                                        'open-ils.proxy.proxy',
                                        [
                                                mw.G.auth_ses[0],
                                                'open-ils.storage',
                                                'open-ils.storage.direct.' + this.db_type + '.retrieve',
                                                array
                                        ]
                                )[0];

                                if (this.cacheable) {
                                        if (this.baseClass.obj_cache[this.classname] == null)
                                                this.baseClass.obj_cache[this.classname] = {};

                                        this.baseClass.obj_cache[this.classname][obj.id()] = obj;
                                }
                        }
                        this.array = obj.array;

                } else {
                        throw new FieldmapperException( "Attempt to build fieldmapper object with something wierd");
                }
        }
}
Fieldmapper.prototype.baseClass = Fieldmapper;
Fieldmapper.prototype.obj_cache = {};
 
Fieldmapper.prototype.clone = function() {
        var obj = new this.constructor();

        for( var i in this.array ) {
                var thing = this.array[i];
                if(thing == null) continue;

                if( thing._isfieldmapper ) {
                        obj.array[i] = thing.clone();
                } else {

                        if(instanceOf(thing, Array)) {
                                obj.array[i] = new Array();

                                for( var j in thing ) {

                                        if( thing[j]._isfieldmapper )
                                                obj.array[i][j] = thing[j].clone();
                                        else
                                                obj.array[i][j] = thing[j];
                                }
                        } else {
                                obj.array[i] = thing;
                        }
                }
        }
        return obj;
}
  
function FieldmapperException(message) {
        this.message = message;
}

FieldmapperException.toString = function() {
        return "FieldmapperException: " + this.message + "\n";

}

	
		<xsl:apply-templates select="opensrf:fieldmapper/opensrf:classes"/>
	</xsl:template>





<!-- sub-templates -->
	<xsl:template match="opensrf:fieldmapper/opensrf:classes">
		<xsl:for-each select="opensrf:class">
			<xsl:apply-templates select="."/>
		</xsl:for-each>
	</xsl:template>




	<xsl:template match="opensrf:class">
		<xsl:apply-templates select="@javascript:class"/>
		<xsl:apply-templates select="opensrf:fields"/>
		<xsl:apply-templates select="opensrf:links/opensrf:link[@cdbi:type='has_many']"/>
	</xsl:template>




	<xsl:template match="opensrf:fields">
		<xsl:apply-templates select="opensrf:field"/>
	</xsl:template>




	<xsl:template match="opensrf:links/opensrf:link[@cdbi:type='has_many']">
		<xsl:variable name="num"><xsl:number/></xsl:variable>
		<xsl:variable name="source"><xsl:value-of select="@source"/></xsl:variable>
		<xsl:variable name="classname"><xsl:value-of select="../../@javascript:class"/></xsl:variable>

// accessor for <xsl:value-of select="$classname"/>:
<xsl:value-of select="$classname"/>.prototype.<xsl:value-of select="@field"/> = function () {
 
	var _pos = <xsl:value-of select="$classname"/>.last_real_field + <xsl:value-of select="$num"/>;
 
	if (!instanceOf(this.array[_pos], Array)) {
		this.array[_pos] = [];
 
	if (this.array[_pos].length == 0) {
		/* get the real thing.
		 * search where <xsl:value-of select="$source"/>.<xsl:value-of select="//*[@id=$source]/opensrf:links/opensrf:link[@cdbi:type='has_a' and @source=$classname]/@field"/>()
		 * equals this.<xsl:value-of select="../../opensrf:fields/opensrf:field[@cdbi:primary='true']/@name"/>();
		 */
	}
 
	return this.array[_pos];
}

	</xsl:template>





	<xsl:template match="@javascript:class">

// Class definition for "<xsl:value-of select="."/>"

function <xsl:value-of select="."/> (array) {

	if (!instanceOf(this, <xsl:value-of select="."/>))
		return new <xsl:value-of select="."/>(array);

	this.baseClass.call(this,array);
	this.classname = "<xsl:value-of select="."/>";
	this._isfieldmapper = true;
	this.uber = <xsl:value-of select="."/>.baseClass.prototype;
}

<xsl:value-of select="."/>.prototype			= new Fieldmapper();
<xsl:value-of select="."/>.prototype.constructor	= <xsl:value-of select="."/>;
<xsl:value-of select="."/>.baseClass			= Fieldmapper;
<xsl:value-of select="."/>.prototype.cachable		= true;
<xsl:value-of select="."/>.prototype.fields		= [];
<xsl:value-of select="."/>.last_real_field		= 2;
 
<!-- XXX This needs to come from somewhere else!!!! -->
<xsl:value-of select="."/>.prototype.db_type		= "<xsl:value-of select="../cdbi:table[@rdbms='Pg']/cdbi:name"/>";
 
<xsl:value-of select="."/>.prototype.isnew = function(new_value) {
        if(arguments.length == 1) { this.array[0] = new_value; }
        return this.array[0];
}
 
<xsl:value-of select="."/>.prototype.ischanged = function(new_value) {
        if(arguments.length == 1) { this.array[1] = new_value; }
        return this.array[1];
}
 
<xsl:value-of select="."/>.prototype.isdeleted = function(new_value) {
        if(arguments.length == 1) { this.array[2] = new_value; }
        return this.array[2];
}
 
	</xsl:template>





	<xsl:template match="opensrf:field">

		<xsl:variable name="num"><xsl:number/></xsl:variable>
		<xsl:variable name="field_pos" select="$num + 2"/>
		<xsl:variable name="last_field_pos" select="$field_pos + 1"/>
		<xsl:variable name="field_name" select="@name"/>

// Accessor/mutator for <xsl:value-of select="../../@javascript:class"/>.<xsl:value-of select="$field_name"/>:
<xsl:value-of select="../../@javascript:class"/>.last_real_field++;
<xsl:value-of select="../../@javascript:class"/>.prototype.fields.push("<xsl:value-of select="$field_name"/>");
<xsl:value-of select="../../@javascript:class"/>.prototype.<xsl:value-of select="$field_name"/> = function (new_value) {

		<xsl:choose>
			<xsl:when test="../../opensrf:links/opensrf:link[@field=$field_name and @cdbi:type='has_a']">
				<xsl:variable
					name="source"
					select="../../opensrf:links/opensrf:link[@field=$field_name and @cdbi:type='has_a']/@source"/>

        if(arguments.length == 1) { this.array[<xsl:value-of select="$field_pos"/>] = new_value; }
        var val = this.array[<xsl:value-of select="$field_pos"/>];

        if (!instanceOf(this.array[<xsl:value-of select="$field_pos"/>], <xsl:value-of select="$source"/>)) {
		if (this.array[<xsl:value-of select="$field_pos"/>] != null) {
                	this.array[<xsl:value-of select="$field_pos"/>] = new <xsl:value-of select="$source"/>(val);
		}
	}

        return this.array[<xsl:value-of select="$field_pos"/>];
			</xsl:when>

			<xsl:otherwise>
	if(arguments.length == 1) { this.array[<xsl:value-of select="$field_pos"/>] = new_value; }
	return this.array[<xsl:value-of select="$field_pos"/>];
			</xsl:otherwise>
		</xsl:choose>
}
	</xsl:template>

</xsl:stylesheet>

