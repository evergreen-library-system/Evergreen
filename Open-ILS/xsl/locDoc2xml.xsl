<xsl:stylesheet version="1.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform">
    <xsl:output omit-xml-declaration="yes" method="xml" encoding="UTF-8" media-type="text/plain" />

    <xsl:template match="/">
    <fields>
        <xsl:for-each select="//a[substring(@href,1,5)='#mrcb']">
            <xsl:call-template name="field">
                <xsl:with-param name="datafieldLabel" select="substring-after(@href,'#')"/>
            </xsl:call-template>
        </xsl:for-each>
    </fields>
    </xsl:template>

    <xsl:template name="field">
        <xsl:param name="datafieldLabel"/>
        <xsl:variable name="locatorAnchor" select="//a[@name=$datafieldLabel]"/>

        <xsl:variable name="tagValue" select="substring-before($locatorAnchor, ' - ')"/>
        <xsl:if test="$tagValue != ''">

            <xsl:variable name="nameStart" select="substring-after($locatorAnchor, ' - ')"/>

            <xsl:variable name="nameValue" select="substring-before($nameStart, '(')"/>

            <xsl:variable name="repeatable" select="substring-after($nameStart, '(')"/>
            <xsl:variable name="description" select="$locatorAnchor/parent::node()/following-sibling::node()/descendant-or-self::*"/>

            <field>
                <xsl:attribute name="tag">
                    <xsl:value-of select="$tagValue"/>
                </xsl:attribute>
                <xsl:attribute name="repeatable">
                    <xsl:choose>
                        <xsl:when test="substring($repeatable,1,1)='R'">
                            <xsl:text>true</xsl:text>
                        </xsl:when>
                        <xsl:otherwise>
                            <xsl:text>false</xsl:text>
                        </xsl:otherwise>
                    </xsl:choose>
                </xsl:attribute>

                <name>
                    <xsl:value-of select="normalize-space($nameValue)"/>
                </name>

                <description>
                    <xsl:value-of select="normalize-space($description)"/>
                </description>

                <xsl:call-template name="indicators">
                    <xsl:with-param name="indUL" select="$locatorAnchor/parent::node()/following-sibling::h3[.='Indicators'][1]/following-sibling::ul[1]"/>
                </xsl:call-template>

                <xsl:if test="substring($tagValue,1,2) != '00'">
                    <xsl:call-template name="subfields">
                        <xsl:with-param name="sfUL" select="$locatorAnchor/parent::node()/following-sibling::h3[.='Subfield Codes'][1]/following-sibling::ul[1]"/>
                    </xsl:call-template>
                </xsl:if>

            </field>

        </xsl:if>
    </xsl:template>

    <xsl:template name="indicators">
        <xsl:param name="indUL"/>
        <xsl:for-each select="$indUL/li">
            <xsl:if test="string-length(substring-after(.,' - Undefi')) = 0">

                <xsl:variable name="indPos">
                    <xsl:choose>
                        <xsl:when test="starts-with(.,'First')">
                            <xsl:text>1</xsl:text>
                        </xsl:when>
                        <xsl:otherwise>
                            <xsl:text>2</xsl:text>
                        </xsl:otherwise>
                    </xsl:choose>
                </xsl:variable>

                <xsl:for-each select="./ul/li">
                    <indicator>
                        <xsl:attribute name="position">
                            <xsl:value-of select="$indPos"/>
                        </xsl:attribute>

                        <xsl:attribute name="value">
                            <xsl:value-of select="substring-before(.,' - ')"/>
                        </xsl:attribute>

                        <description>
                            <xsl:value-of select="normalize-space(substring-after(.,' - '))"/>
                        </description>
                    </indicator>
                </xsl:for-each>
            </xsl:if>
        </xsl:for-each>
    </xsl:template>

    <xsl:template name="subfields">
        <xsl:param name="sfUL"/>
        <xsl:for-each select="$sfUL/li">
            <xsl:variable name="sfCode" select="substring-before(., ' - ')"/>
            <xsl:variable name="descStart" select="substring-after(., ' - ')"/>
            <xsl:variable name="descValue" select="substring-before($descStart, '(')"/>
            <xsl:variable name="sfRepeatable" select="substring-after(., '(')"/>

            <subfield>
                <xsl:attribute name="code">
                    <xsl:value-of select="substring($sfCode,2,1)"/>
                </xsl:attribute>

                <xsl:attribute name="repeatable">
                    <xsl:choose>
                        <xsl:when test="substring($sfRepeatable,1,1)='R'">
                            <xsl:text>true</xsl:text>
                        </xsl:when>
                        <xsl:otherwise>
                            <xsl:text>false</xsl:text>
                        </xsl:otherwise>
                    </xsl:choose>
                </xsl:attribute>

                <description>
                    <xsl:value-of select="normalize-space($descValue)"/>
                </description>
            </subfield>
        </xsl:for-each>
    </xsl:template>

</xsl:stylesheet>

