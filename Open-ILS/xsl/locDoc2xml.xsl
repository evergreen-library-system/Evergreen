<!--

Copyright (C) 2008 Equinox Software, Inc.
Mike Rylander <miker@esilibrary.com>

This program is free software; you can redistribute it and/or
modify it under the terms of the GNU General Public License
as published by the Free Software Foundation; either version 2
of the License, or (at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program; if not, write to the Free Software
Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA

-->


<!--

This XSLT will take the MARC21 Concise Format for Bibliographic Data
documentation maintained by the Library of Congress and turn it into an XML
document for use by Evergreen (and others, if you so desire, under the terms
of the GPL).  The LoC docs are available from:

 http://www.loc.gov/marc/bibliographic/

The format of the output XML is similar to that produced sometime during
2005 by Ed Summers and shared at textualize.com.  That site was not available
at the time of this XSLT's creation, and thus this exists.

Please report any problems to Mike Rylander at <miker@esilibrary.com>.

Here's an easy way to use this:

curl -o - http://www.loc.gov/marc/bibliographic/ecbd{ldrd,cntr,007s,008s,numb,clas,main,tils,impr,phys,sers,not1,not2,subj,adde,link,srae,hold}.html | \
 tidy -asxml -n -q -utf8 | \
 xsltproc -\-html -\-novalid locDoc2xml.xsl - | \
 xmllint -\-format -\-noblanks - > marcedit-tooltips.xml

-->


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

