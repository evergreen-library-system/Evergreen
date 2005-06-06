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
	<xsl:strip-space elements="*"/>

	<xsl:template match="/">
		<xsl:apply-templates select="opensrf:fieldmapper/opensrf:classes"/>
1;
	</xsl:template>


	<!-- sub-templates -->
	<xsl:template match="opensrf:classes">
		<xsl:for-each select="opensrf:class">
			<xsl:sort select="@id"/>
			<xsl:apply-templates select="."/>
		</xsl:for-each>
		<xsl:apply-templates select="opensrf:class/opensrf:links/opensrf:link[@type='has_a']"/>
		<xsl:apply-templates select="opensrf:class/opensrf:links/opensrf:link[@type='has_many']"/>
	</xsl:template>


	
	<xsl:template match="opensrf:class">
		#-------------------------------------------------------------------------------
		# <xsl:value-of select="$driver"/> Class definition for "<xsl:value-of select="@id"/>" (<xsl:value-of select="cdbi:class"/>)
		#-------------------------------------------------------------------------------
		package <xsl:value-of select="@cdbi:class"/>;
		use base '<xsl:value-of select="cdbi:superclass"/>';

		__PACKAGE__->table("<xsl:value-of select="database:table[@rdbms=$driver]/database:name"/>");
		<xsl:if test="database:table[@rdbms=$driver]/database:sequence">
			__PACKCAGE__->sequence("<xsl:value-of select="database:table[@rdbms=$driver]/database:sequence"/>");
		</xsl:if>

		__PACKAGE__->columns(Primary => <xsl:apply-templates select="opensrf:fields/opensrf:field[@database:primary='true']"/>);
		<xsl:if test="opensrf:fields/opensrf:field[@database:required='true' and not(@database:primary='true')]">
			__PACKAGE__->columns(
				Essential => <xsl:apply-templates
						select="opensrf:fields/opensrf:field[@database:required='true' and not(@database:primary='true')]"/>
			);
		</xsl:if>
		<xsl:if test="opensrf:fields/opensrf:field[not(@database:required='true') and not(@database:primary='true')]">
			__PACKAGE__->columns(
				Others => <xsl:apply-templates
						select="opensrf:fields/opensrf:field[not(@database:required='true') and not(@database:primary='true')]"/>
			);
		</xsl:if>
	</xsl:template>



	<xsl:template match="database:table">
	</xsl:template>



	<xsl:template match="opensrf:field">
		'<xsl:value-of select='@name'/>',
	</xsl:template>



	<xsl:template match="opensrf:link">
		<xsl:variable name='source' select='@source'/>
		<xsl:value-of select="../../@cdbi:class"/>-><xsl:value-of select="@type"/>(
			<xsl:value-of select="@field"/> => '<xsl:value-of select="//*[@id=$source]/@cdbi:class"/>'
		);

	</xsl:template>
</xsl:stylesheet>

