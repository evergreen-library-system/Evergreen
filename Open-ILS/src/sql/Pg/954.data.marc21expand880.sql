UPDATE config.xml_transform SET xslt = $$<?xml version="1.0" encoding="UTF-8"?>
<xsl:stylesheet
    xmlns:xsl="http://www.w3.org/1999/XSL/Transform" 
    xmlns:marc="http://www.loc.gov/MARC21/slim"
    version="1.0">
<!--
Copyright (C) 2010  Equinox Software, Inc.
Galen Charlton <gmc@esilibrary.cOM.

This program is free software; you can redistribute it and/or
modify it under the terms of the GNU General Public License
as published by the Free Software Foundation; either version 2
of the License, or (at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

marc21_expand_880.xsl - stylesheet used during indexing to
                        map alternative graphical representations
                        of MARC fields stored in 880 fields
                        to the corresponding tag name and value.

For example, if a MARC record for a Chinese book has

245.00 $6 880-01 $a Ba shi san nian duan pian xiao shuo xuan
880.00 $6 245-01/$1 $a八十三年短篇小說選

this stylesheet will transform it to the equivalent of

245.00 $6 880-01 $a Ba shi san nian duan pian xiao shuo xuan
245.00 $6 245-01/$1 $a八十三年短篇小說選

-->
    <xsl:output encoding="UTF-8" indent="yes" method="xml"/>

    <xsl:template match="@*|node()">
        <xsl:copy>
            <xsl:apply-templates select="@*|node()"/>
        </xsl:copy>
    </xsl:template>

    <xsl:template match="//marc:datafield[@tag='880']">
        <xsl:if test="./marc:subfield[@code='6'] and string-length(./marc:subfield[@code='6']) &gt;= 6">
            <marc:datafield>
                <xsl:attribute name="tag">
                    <xsl:value-of select="substring(./marc:subfield[@code='6'], 1, 3)" />
                </xsl:attribute>
                <xsl:attribute name="ind1">
                    <xsl:value-of select="@ind1" />
                </xsl:attribute>
                <xsl:attribute name="ind2">
                    <xsl:value-of select="@ind2" />
                </xsl:attribute>
                <xsl:apply-templates />
            </marc:datafield>
        </xsl:if>
    </xsl:template>
    
</xsl:stylesheet>$$
where name = 'marc21expand880';
