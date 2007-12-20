<xsl:stylesheet version="1.0" xmlns:xlink="http://www.w3.org/TR/xlink" xmlns:marc="http://www.loc.gov/MARC21/slim" xmlns:xsl="http://www.w3.org/1999/XSL/Transform" exclude-result-prefixes="marc" xmlns="http://open-ils.org/spec/opensrf/ACQ/bibdata/v1">
        <xsl:output method="xml" indent="yes"/>

	<xsl:template match="/">
		<xsl:apply-templates/>
	</xsl:template>

	<xsl:template match="marc:record">
		<bibdata>

		<!-- language -->
		<xsl:choose>
			<xsl:when test="marc:datafield[@tag='240']/marc:subfield[@code='l']">
				<xsl:for-each select="marc:datafield[@tag='240']/marc:subfield[@code='l']">
					<language><xsl:value-of select="."/></language>
				</xsl:for-each>
			</xsl:when>
			<xsl:when test="marc:datafield[@tag='041']/marc:subfield[@code='a']">
				<xsl:for-each select="marc:datafield[@tag='041']/marc:subfield[@code='a'][1]">
					<language><xsl:value-of select="."/></language>
				</xsl:for-each>
			</xsl:when>
			<xsl:when test="//marc:controlfield[@tag='008']">
				<language><xsl:value-of select="substring(//marc:controlfield[@tag='008']/text(),36,3)"/></language>
			</xsl:when>
		</xsl:choose>

		<!-- title -->
		<xsl:for-each select="marc:datafield[@tag='245'][1]">
			<title>
				<xsl:call-template name="subfieldSelect">
					<xsl:with-param name="codes">abcmnopr</xsl:with-param>
				</xsl:call-template>
			</title>

			<xsl:if test="marc:subfield[@code='k']">
				<forms>
					<xsl:for-each select="marc:subfield[@code='k']">
						<form><xsl:value-of select="."/></form>
					</xsl:for-each>
				</forms>
			</xsl:if>

			<xsl:for-each select="marc:subfield[@code='h']">
				<medium><xsl:value-of select="."/></medium>
			</xsl:for-each>
		</xsl:for-each>

		<!-- author -->
		<xsl:for-each select="marc:datafield[@tag='100' or @tag='110' or @tag='113']">
			<author>
				<xsl:call-template name="subfieldSelect">
					<xsl:with-param name="codes">ad</xsl:with-param>
				</xsl:call-template>
			</author>
		</xsl:for-each>

		<!-- publisher -->
		<xsl:for-each select="marc:datafield[@tag='260']">
			<publisher>
				<xsl:call-template name="subfieldSelect">
					<xsl:with-param name="codes">b</xsl:with-param>
				</xsl:call-template>
			</publisher>
		</xsl:for-each>

		<!-- pubdate -->
		<xsl:for-each select="marc:datafield[@tag='260']">
			<pubdate>
				<xsl:call-template name="subfieldSelect">
					<xsl:with-param name="codes">c</xsl:with-param>
				</xsl:call-template>
			</pubdate>
		</xsl:for-each>

		<!-- edition -->
		<xsl:for-each select="marc:datafield[@tag='250']">
			<edition>
				<xsl:call-template name="subfieldSelect">
					<xsl:with-param name="codes">a</xsl:with-param>
				</xsl:call-template>
			</edition>
		</xsl:for-each>

		<!-- pagination -->
		<xsl:for-each select="marc:datafield[@tag='300']">
			<pagination>
				<xsl:call-template name="subfieldSelect">
					<xsl:with-param name="codes">a</xsl:with-param>
				</xsl:call-template>
			</pagination>
		</xsl:for-each>

		<!-- physicalSize -->
		<xsl:for-each select="marc:datafield[@tag='300']">
			<physicalSize>
				<xsl:call-template name="subfieldSelect">
					<xsl:with-param name="codes">c</xsl:with-param>
				</xsl:call-template>
			</physicalSize>
		</xsl:for-each>

		<!-- isbn -->
		<xsl:for-each select="marc:datafield[@tag='020']">
			<isbns>
				<xsl:for-each select=".">
					<isbn>
						<xsl:call-template name="subfieldSelect">
							<xsl:with-param name="codes">a</xsl:with-param>
						</xsl:call-template>
					</isbn>
				</xsl:for-each>
			</isbns>
		</xsl:for-each>

		<!-- issn -->
		<xsl:for-each select="marc:datafield[@tag='022']">
			<issns>
				<xsl:for-each select=".">
					<issn>
						<xsl:call-template name="subfieldSelect">
							<xsl:with-param name="codes">a</xsl:with-param>
						</xsl:call-template>
					</issn>
				</xsl:for-each>
			</issns>
		</xsl:for-each>

		<!-- price -->
		<xsl:for-each select="marc:datafield[(@tag='020' or @tag='022') and marc:subfield[@code='c']][1]">
			<price>
				<xsl:call-template name="subfieldSelect">
					<xsl:with-param name="codes">c</xsl:with-param>
				</xsl:call-template>
			</price>
		</xsl:for-each>

		</bibdata>
	</xsl:template>

        <xsl:template name="subfieldSelect">
                <xsl:param name="codes"/>
                <xsl:param name="delimeter"><xsl:text> </xsl:text></xsl:param>
                <xsl:variable name="str">
                        <xsl:for-each select="marc:subfield">
                                <xsl:if test="contains($codes, @code)">
                                        <xsl:value-of select="text()"/><xsl:value-of select="$delimeter"/>
                                </xsl:if>
                        </xsl:for-each>
                </xsl:variable>
                <xsl:value-of select="substring($str,1,string-length($str)-string-length($delimeter))"/>
        </xsl:template>

</xsl:stylesheet>
