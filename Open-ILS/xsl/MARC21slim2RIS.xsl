<?xml version="1.0" encoding="UTF-8"?>
<xsl:stylesheet version="1.0" xmlns:marc="http://www.loc.gov/MARC21/slim" xmlns:xsl="http://www.w3.org/1999/XSL/Transform" exclude-result-prefixes="marc">
    <xsl:include href="MARC21slimUtils.xsl"/>
    <xsl:output method="text"/>

    <xsl:template match="marc:record">
        <xsl:variable name="leader" select="marc:leader" />
        <xsl:variable name="leader6" select="substring($leader,7,1)" />
        <xsl:variable name="leader7" select="substring($leader,8,1)" />

        <xsl:text>&#10;TY  - </xsl:text>

        <xsl:variable name="field008" select="marc:controlfield[@tag=008]"/>

        <xsl:choose>
            <xsl:when test="$leader6='a' or $leader6='t'">
                <xsl:choose>
                    <xsl:when test="$leader6='a' and $leader7='b' or $leader7='i' or $leader7='s'">
                        <!-- Continuing Resource -->
                        <xsl:variable name="field008-21" select="substring($field008,22,1)"/>
                        <xsl:choose>
                            <xsl:when test="$field008-21='p'">JOUR</xsl:when>
                            <xsl:when test="$field008-21='n'">NEWS</xsl:when>
                            <xsl:when test="$field008-21='m'">SER</xsl:when>

                            <!-- Default to Journal -->
                            <xsl:otherwise>JOUR</xsl:otherwise>
                        </xsl:choose>
                    </xsl:when>
                    <xsl:otherwise>
                        <!-- If not a CR, then a book (or book-type) item -->
                        <xsl:variable name="field008-24-27" select="substring($field008,25,4)"/>
                        <xsl:variable name="field008-29" select="substring($field008,30,1)"/>

                        <xsl:choose>
                            <xsl:when test="$leader6='a' and $leader7='m'">BOOK</xsl:when> 
                            <xsl:when test="$leader6='a' and $leader7='a'">CHAP</xsl:when> 
                            <xsl:when test="$field008-29='1'">CONF</xsl:when> 
                            <xsl:when test="$field008-24-27='m'">THES</xsl:when> 
                            <xsl:when test="$field008-24-27='a'">ABST</xsl:when> 
                            <xsl:when test="$field008-24-27='j'">PAT</xsl:when> 
                            <xsl:when test="$field008-24-27='v'">CASE</xsl:when> 
                            <xsl:when test="$field008-24-27='l'">STAT</xsl:when> 
                            <xsl:when test="$field008-24-27='t'">RPRT</xsl:when> 
                            <xsl:when test="$field008-24-27='c'">CTLG</xsl:when> 

                            <!-- Default to BOOK -->
                            <xsl:otherwise>BOOK</xsl:otherwise>
                        </xsl:choose>
                    </xsl:otherwise>
                </xsl:choose>
            </xsl:when>

            <xsl:when test="$leader6='e' or $leader6='f'">MAP</xsl:when>
            <xsl:when test="$leader6='i' or $leader6='j'">SOUND</xsl:when>
            <xsl:when test="$leader6='c' or $leader6='d'">MUSIC</xsl:when>

            <xsl:when test="$leader6='g'">
                <xsl:variable name="field008-33" select="substring($field008,34,1)"/>
                <xsl:choose>
                    <xsl:when test="$field008-33='m' or $field008-33='f'">MPCT</xsl:when>
                    <xsl:when test="$field008-33='v'">VIDEO</xsl:when>
                    <xsl:when test="$field008-33='s'">SLIDE</xsl:when>

                    <!-- Default to Motion Picture -->
                    <xsl:otherwise>MPCT</xsl:otherwise>
                </xsl:choose>
            </xsl:when>
            <xsl:when test="$leader6='k' or $leader6='r'">
                <xsl:variable name="field008-33" select="substring($field008,34,1)"/>
                <xsl:choose>
                    <xsl:when test="$field008-33='a' or $field008-33='c' or $field008-33='i' or $field008-33='k'">ART</xsl:when>

                    <!-- Default to Generic -->
                    <xsl:otherwise>GEN</xsl:otherwise>
                </xsl:choose>
            </xsl:when>

            <xsl:when test="$leader6='m'">
                <xsl:variable name="field008-26" select="substring($field008,27,1)"/>
                <xsl:choose>
                    <xsl:when test="$field008-26='b'">COMP</xsl:when>
                    <xsl:when test="$field008-26='e'">ELEC</xsl:when>
                    <xsl:when test="$field008-26='a' or $field008-26='c' or $field008-26='d'">DATA</xsl:when>

                    <!-- Default to Computer File -->
                    <xsl:otherwise>COMP</xsl:otherwise>
                </xsl:choose>
            </xsl:when>

            <xsl:otherwise>GEN</xsl:otherwise>

        </xsl:choose> <!-- End TY -->


        <xsl:for-each select="marc:datafield[@tag=100]|marc:datafield[@tag=110]|marc:datafield[@tag=111]">
            <xsl:text>&#10;A1  - </xsl:text>
            <xsl:for-each select="marc:subfield[@code='a']">
                <xsl:call-template name="chopPunctuation">
                    <xsl:with-param name="punctuation">
                        <xsl:text>,; </xsl:text>
                    </xsl:with-param>
                    <xsl:with-param name="chopString">
                        <xsl:value-of select="."/>
                    </xsl:with-param>
                </xsl:call-template>
            </xsl:for-each>
            <xsl:if test="@tag = '110'">
                <xsl:for-each select="marc:subfield[@code='b']">
                    <xsl:value-of select="."/>
                </xsl:for-each>
            </xsl:if>
            <xsl:if test="@tag = '111'">
                <xsl:for-each select="marc:subfield[@code='q']">
                    <xsl:value-of select="."/>
                </xsl:for-each>
                <xsl:for-each select="marc:subfield[@code='e']">
                    <xsl:value-of select="."/>
                </xsl:for-each>
            </xsl:if>
        </xsl:for-each>
        
        <xsl:for-each select="marc:datafield[@tag=245]">
            <xsl:text>&#10;T1  - </xsl:text>
            <xsl:for-each select="marc:subfield[@code='a']">
                <xsl:call-template name="chopPunctuation">
                    <xsl:with-param name="punctuation">
                        <xsl:text>:/ </xsl:text>
                    </xsl:with-param>
                    <xsl:with-param name="chopString">
                        <xsl:value-of select="."/>
                    </xsl:with-param>
                </xsl:call-template>
            </xsl:for-each>
            <xsl:for-each select="marc:subfield[@code='b']">
                <xsl:text>: </xsl:text>
                <xsl:call-template name="chopPunctuation">
                    <xsl:with-param name="punctuation">
                        <xsl:text>/ </xsl:text>
                    </xsl:with-param>
                    <xsl:with-param name="chopString">
                        <xsl:value-of select="."/>
                    </xsl:with-param>
                </xsl:call-template>
            </xsl:for-each>
        </xsl:for-each>

        <xsl:variable name="respStmt" select="marc:datafield[@tag=245]/marc:subfield[@code='c']"/>

        <xsl:for-each select="marc:datafield[@tag=700]">
            <xsl:for-each select="marc:subfield[@code='a']">
                <xsl:variable name="addedAuthor" select="."/>
                <xsl:choose>
                    <xsl:when test="contains($respStmt, substring-before($addedAuthor, ', '))">
                        <xsl:text>&#10;A1  - </xsl:text>
                        <xsl:call-template name="chopPunctuation">
                            <xsl:with-param name="punctuation">
                                <xsl:text>,; </xsl:text>
                            </xsl:with-param>
                            <xsl:with-param name="chopString">
                                <xsl:value-of select="$addedAuthor"/>
                            </xsl:with-param>
                        </xsl:call-template>
                    </xsl:when>
                    <xsl:otherwise>
                        <xsl:text>&#10;A2  - </xsl:text>
                        <xsl:call-template name="chopPunctuation">
                            <xsl:with-param name="punctuation">
                                <xsl:text>,; </xsl:text>
                            </xsl:with-param>
                            <xsl:with-param name="chopString">
                                <xsl:value-of select="$addedAuthor"/>
                            </xsl:with-param>
                        </xsl:call-template>
                    </xsl:otherwise>
                </xsl:choose>
            </xsl:for-each>
        </xsl:for-each>

        <xsl:for-each select="marc:datafield[@tag=710]">
            <xsl:text>&#10;A2  - </xsl:text>
            <xsl:for-each select="marc:subfield[@code='a']|marc:subfield[@code='b']">
                <xsl:value-of select="."/>
            </xsl:for-each>
        </xsl:for-each>

        <xsl:for-each select="marc:datafield[@tag=490]|marc:datafield[@tag=711]">
            <xsl:for-each select="marc:subfield[@code='a']">
                <xsl:text>&#10;T3  - </xsl:text>
                <xsl:value-of select="."/>
            </xsl:for-each>
            <xsl:if test="@tag = '711'">
                <xsl:for-each select="marc:subfield[@code='q']">
                    <xsl:value-of select="."/>
                </xsl:for-each>
                <xsl:for-each select="marc:subfield[@code='e']">
                    <xsl:value-of select="."/>
                </xsl:for-each>
            </xsl:if>
        </xsl:for-each>

        <xsl:for-each select="marc:datafield[@tag=210]">
            <xsl:text>&#10;JO  - </xsl:text>
            <xsl:for-each select="marc:subfield[@code='a']">
                <xsl:value-of select="."/>
            </xsl:for-each>
        </xsl:for-each>

        <xsl:for-each select="marc:datafield[@tag=222]">
            <xsl:text>&#10;JF  - </xsl:text>
            <xsl:for-each select="marc:subfield[@code='a']">
                <xsl:value-of select="."/>
            </xsl:for-each>
        </xsl:for-each>

        <xsl:for-each select="marc:datafield[@tag=260]">
            <xsl:for-each select="marc:subfield[@code='a']">
                <xsl:text>&#10;CY  - </xsl:text>
                <xsl:call-template name="chopPunctuation">
                    <xsl:with-param name="punctuation">
                        <xsl:text> :</xsl:text>
                    </xsl:with-param>
                    <xsl:with-param name="chopString">
                        <xsl:value-of select="."/>
                    </xsl:with-param>
                </xsl:call-template>
            </xsl:for-each>
            <xsl:for-each select="marc:subfield[@code='b']">
                <xsl:text>&#10;PB  - </xsl:text>
                <xsl:call-template name="chopPunctuation">
                    <xsl:with-param name="punctuation">
                        <xsl:text> ,</xsl:text>
                    </xsl:with-param>
                    <xsl:with-param name="chopString">
                        <xsl:value-of select="."/>
                    </xsl:with-param>
                </xsl:call-template>
            </xsl:for-each>
            <xsl:for-each select="marc:subfield[@code='c']">
                <xsl:text>&#10;PY  - </xsl:text>
                <xsl:call-template name="chopPunctuation">
                    <xsl:with-param name="punctuation">
                        <xsl:text> .</xsl:text>
                    </xsl:with-param>
                    <xsl:with-param name="chopString">
                        <xsl:value-of select="."/>
                    </xsl:with-param>
                </xsl:call-template>
                <xsl:text>///</xsl:text>
            </xsl:for-each>
        </xsl:for-each>

        <xsl:for-each select="marc:datafield[@tag=520]">
            <xsl:for-each select="marc:subfield[@code='a']">
                <xsl:text>&#10;N2  - </xsl:text>
                <xsl:value-of select="."/>
            </xsl:for-each>
        </xsl:for-each>

        <xsl:for-each select="marc:datafield[@tag=650]|marc:datafield[@tag=651]">
            <xsl:for-each select="marc:subfield">
                <xsl:text>&#10;KW  - </xsl:text>
                <xsl:value-of select="."/>
            </xsl:for-each>
        </xsl:for-each>

        <xsl:for-each select="marc:datafield[@tag=856]">
            <xsl:for-each select="marc:subfield[@code='u']">
                <xsl:text>&#10;UR  - </xsl:text>
                <xsl:value-of select="."/>
            </xsl:for-each>
        </xsl:for-each>

        <xsl:for-each select="marc:datafield[@tag=020]|marc:datafield[@tag=022]">
            <xsl:text>&#10;SN  - </xsl:text>
            <xsl:for-each select="marc:subfield[@code='a']">
                <xsl:value-of select="."/>
            </xsl:for-each>
        </xsl:for-each>

        <xsl:text>&#10;ER  -&#10;</xsl:text>
	</xsl:template>
</xsl:stylesheet>

