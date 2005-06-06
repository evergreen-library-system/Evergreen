<xsl:stylesheet
	version='1.0'
	xmlns:xsl='http://www.w3.org/1999/XSL/Transform'
	xmlns:opensrf="http://opensrf.org/xmlns/opensrf"
	xmlns:cdbi="http://opensrf.org/xmlns/opensrf/cdbi"
	xmlns:database="http://opensrf.org/xmlns/opensrf/database"
	xmlns:perl="http://opensrf.org/xmlns/opensrf/perl"
	xmlns:javascript="http://opensrf.org/xmlns/opensrf/javascript"
	xmlns:c="http://opensrf.org/xmlns/opensrf/c">
	<xsl:output method="text" />
	<xsl:strip-space elements="xsl:*"/>
	<xsl:variable name="last_field_pos"/>

	<xsl:template match="/">
package Fieldmapper;
use JSON;
use Data::Dumper;
use base 'OpenSRF::Application';

use OpenSRF::Utils::Logger;
my $log = 'OpenSRF::Utils::Logger';

sub new {                                                            
        my $self = shift;                                            
        my $value = shift;                                              
	if (defined $value) {
		if (!ref($value) or ref($value) ne 'ARRAY') {
			# go fetch the object by id...
		}
        } else {
		$value = [];
	}
        return bless $value => $self->class_name;                    
}

sub decast {
        my $self = shift;
        return [ @$self ];
}       

sub DESTROY {} 

sub class_name {
        my $class_name = shift;
        return ref($class_name) || $class_name;
}

sub isnew { return $_[0][0]; }
sub ischanged { return $_[0][1]; }
sub isdeleted { return $_[0][2]; }


		<xsl:apply-templates select="opensrf:fieldmapper/opensrf:classes"/>

1;
	</xsl:template>





<!-- sub-templates -->
	<xsl:template match="opensrf:fieldmapper/opensrf:classes">
		<xsl:for-each select="opensrf:class">
			<xsl:sort select="@id"/>
			<xsl:apply-templates select="."/>
			<xsl:apply-templates select="opensrf:links/opensrf:link[@type='has_many']"/>
		</xsl:for-each>
	</xsl:template>




	<xsl:template match="opensrf:class">
		<xsl:apply-templates select="@perl:class"/>
		<xsl:apply-templates select="opensrf:fields"/>
	</xsl:template>




	<xsl:template match="opensrf:fields">
		<xsl:apply-templates select="opensrf:field"/>
	</xsl:template>





	<xsl:template match="@perl:class">
 
#-------------------------------------------------------------------------------
# Class definition for "<xsl:value-of select="."/>"
#-------------------------------------------------------------------------------
 
package <xsl:value-of select="."/>;
use base "<xsl:value-of select="../perl:superclass"/>";

{	my @real;
	sub real_fields {
		push @real, @_ if (@_);
		return @real;
	}
}

{	my $last_real;
	sub last_real_field : lvalue {
		$last_real;
	}
}

	<xsl:if test="../@cdbi:class">
sub cdbi {
	return "<xsl:value-of select="../@cdbi:class"/>";
}
	</xsl:if>

sub json_hint {
        return "<xsl:value-of select="../@id"/>";
}


sub is_virtual {
	<xsl:choose>
		<xsl:when test="../@virutal">
	return 1;
		</xsl:when>
		<xsl:otherwise>
	return 0;
		</xsl:otherwise>
	</xsl:choose>
}

	</xsl:template>





	<!-- scalar valued fields and "has_a" relationships -->
	<xsl:template match="opensrf:field">

		<xsl:variable name="num"><xsl:number/></xsl:variable>
		<xsl:variable name="field_pos" select="$num + 2"/>
		<xsl:variable name="last_field_pos" select="$field_pos + 1"/>
		<xsl:variable name="field_name" select="@name"/>
		<xsl:variable name="classname" select="../../@perl:class"/>

# Accessor/mutator for <xsl:value-of select="$classname"/>::<xsl:value-of select="$field_name"/>:
__PACKAGE__->last_real_field()++;
__PACKAGE__->real_fields("<xsl:value-of select="$field_name"/>");
sub <xsl:value-of select="$field_name"/> {
	my $self = shift;
	my $new_val = shift;
	$self->[<xsl:value-of select="$field_pos"/>] = $new_val if (defined $new_val);

		<xsl:if test="../../opensrf:links/opensrf:link[@field=$field_name and @type='has_a']">
			<!-- We have a fkey on this field.  Go fetch the referenced object. -->
			<xsl:variable
				name="source"
				select="../../opensrf:links/opensrf:link[@field=$field_name and @type='has_a']/@source"/>
			<xsl:variable
				name="sourceclass"
				select="//*[@id=$source]/@perl:class"/>

        my $val = $self->[<xsl:value-of select="$field_pos"/>];

	if (defined $self->[<xsl:value-of select="$field_pos"/>]) {
		if (!UNIVERSAL::isa($self->[<xsl:value-of select="$field_pos"/>], <xsl:value-of select="$sourceclass"/>)) {
                	$self->[<xsl:value-of select="$field_pos"/>] = <xsl:value-of select="$sourceclass"/>->new($val);
		}
	}
		</xsl:if>

	return $self->[<xsl:value-of select="$field_pos"/>];
}


sub clear_<xsl:value-of select="$field_name"/> {
	my $self = shift;
	$self->[<xsl:value-of select="$field_pos"/>] = undef;
	return 1;
}

	</xsl:template>






	<!-- "has_many" relationships -->
	<xsl:template match="opensrf:links/opensrf:link[@type='has_many']">
		<xsl:variable name="num"><xsl:number/></xsl:variable>
		<xsl:variable name="source"><xsl:value-of select="@source"/></xsl:variable>
		<xsl:variable name="sourceclass"><xsl:value-of select="//*[@id=$source]/@perl:class"/></xsl:variable>
		<xsl:variable name="classname"><xsl:value-of select="../../@perl:class"/></xsl:variable>
		<xsl:variable name="id"><xsl:value-of select="../../@id"/></xsl:variable>
		<xsl:variable name="fkey" select="//*[@id=$source]/opensrf:links/opensrf:link[@type='has_a' and @source=$id]/@field"/>
		<xsl:variable name="pkey" select="../../opensrf:fields/opensrf:field[@database:primary='true']/@name"/>

# accessor for <xsl:value-of select="$classname"/>::<xsl:value-of select="@field"/>:
sub <xsl:value-of select="@field"/> {
	my $self = shift;
 
	my $_pos = <xsl:value-of select="$classname"/>->last_real_field + <xsl:value-of select="$num"/>;
 
	if (!ref($self->[$_pos]) ne 'ARRAY') {
		$self->[$_pos] = [];
 
	if (@{$self->[$_pos]} == 0) {
		# get the real thing.
		# search where <xsl:value-of select="$sourceclass"/>-><xsl:value-of select="$fkey"/> == $self-><xsl:value-of select="$pkey"/>;
	}
 
	return $self->[$_pos];
}

	</xsl:template>




</xsl:stylesheet>

