<?xml version="1.0" encoding="UTF-8"?>
<!--

!! Information About This File: http://opensearch.a9.com/docs/stylesheet.jsp

Copyright (c) 2005-2006 A9.com, Inc. or its affiliates.

Author: Michael Fagan, parts by Joel Tesler
Changelog:
	2005-11-28: Updated to work with OpenSearch 1.1 Draft 2 (rather than Draft 1)
	2005-10-19: Changlog added (unknown update)
Description: Converts an OpenSearch feed into XHTML.
	Can handle
		OpenSearch 1.0 and 1.1 Draft 2
		RSS 0.9, 0.91, 0.92, 0.93, 1.0, 2.0 and Atom 1.0
		(suggested searches using OpenSearch 1.1 Query is not yet handled)
	Also handles lack of data and errors very well and flexibly. (This is not a strict parser; invalid responses may appear okay)
	This file should be bunled with a CSS and a Javascript file, the latter is necessary to handle XSLT parsers (e.g. Mozilla-based) that do not support disable-output-escaping
Note:
	Javascript and other potentially malicious code is *not* dealt with
To-do list:
	don't separate authors or categories with a ';' if there's only one of them
	webMaster (rss) not used due to duplication with managingEditor... really should be able to detect dupes...
	use dc:source
	use rating (rss)
	for link to html version (ideal) for atom make sure alternate link is (x)html (one of list of mime types?)
	handle common rss/atom extensions (*dc*, geo, vcard, foaf, doap, pheed, media rss, itunes, slash, licenses, etc)
-->
<xsl:stylesheet version="1.0"
 xmlns="http://www.w3.org/1999/xhtml"
 xmlns:xsl="http://www.w3.org/1999/XSL/Transform"
 xmlns:opensearch="http://a9.com/-/spec/opensearch/1.1/"
 xmlns:opensearchOld="http://a9.com/-/spec/opensearchrss/1.0/"
 xmlns:atom="http://www.w3.org/2005/Atom"
 xmlns:rss9="http://my.netscape.com/rdf/simple/0.9/"
 xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#"
 xmlns:rss1="http://purl.org/rss/1.0/"
 xmlns:content="http://purl.org/rss/1.0/modules/content/"
 xmlns:dc="http://purl.org/dc/elements/1.1/"
 xmlns:xhtml="http://www.w3.org/1999/xhtml"
 exclude-result-prefixes="xsl opensearch opensearchOld atom rss9 rdf rss1 content dc xhtml"
 >
	<xsl:output omit-xml-declaration="yes" method="html" doctype-public="-//W3C/DTD HTML 4.01 Transitional//EN" doctype-system="http://www.w3.org/TR/html4/strict.dtd" encoding="UTF-8" media-type="text/html" />
	
	<!-- START SETTINGS -->
	<!-- text used; change this for translation and also some settings -->
	<xsl:variable name="t-lang">en-US</xsl:variable> <!-- the ISO 639 code the the language that the text (the texts below) are in -->
	<!-- next 2 vars are the title and description of error no rss/atom feed found -->
	<xsl:variable name="t-errortitle">Can't Display Search Results</xsl:variable>
	<xsl:variable name="t-errordesc">Sorry, there was a problem displaying search results. No valid response was found. Try contacting the owner of this website for assistance.</xsl:variable>
	<!-- next 4 vars used in <link> tags in the <head> -->
	<xsl:variable name="t-prevpage">previous page of search results</xsl:variable>
	<xsl:variable name="t-nextpage">next page of search results</xsl:variable>
	<xsl:variable name="t-firstpage">first page of search results</xsl:variable>
	<xsl:variable name="t-lastpage">last page of search results</xsl:variable>
	<!-- next 3 vars example: "Results 1 to 10 of 35" -->
	<xsl:variable name="t-results">Results</xsl:variable>
	<xsl:variable name="t-resultsto">to</xsl:variable>
	<xsl:variable name="t-resultsof">of</xsl:variable>
	<xsl:variable name="t-resultstitle">Search Results</xsl:variable> <!-- used in case of absent title -->
	<xsl:variable name="t-resultsfor">Search Results for</xsl:variable> <!-- used in case of absent title but query is known -->
	<!-- next 2 vars are text links to previous and next result pages; entitles should be double-escaped as shown -->
	<xsl:variable name="t-prevlink">&amp;#171; previous</xsl:variable>
	<xsl:variable name="t-nextlink">next &amp;#187;</xsl:variable>
	<xsl:variable name="t-nomoreresults">No further results.</xsl:variable> <!-- shown when the page is beyond the last page of results -->
	<xsl:variable name="t-noresults">Sorry, no results were found.</xsl:variable>
	<xsl:variable name="t-untitleditem">(untitled)</xsl:variable> <!-- text of untitled items when the title needs to be shown) -->
	<xsl:variable name="t-entrylink">view full entry</xsl:variable> <!-- text of the link to the full entry (used with <content src="" /> in atom) -->
	<xsl:variable name="t-authors">by</xsl:variable> <!-- label before one or more author/contributors (eg the 'by' in 'by Joe'); leave blank to not show authors -->
	<xsl:variable name="t-categories">Subjects:</xsl:variable> <!-- label before one or more categories; leave blank to not show categories -->
	<xsl:variable name="t-source">from</xsl:variable> <!-- label of source (e.g. 'from' or 'via' in English); leave blank to not show sources -->
	<xsl:variable name="t-comments">comments</xsl:variable> <!-- leave blank to not show link to comments -->
	<xsl:variable name="t-download">download</xsl:variable> <!-- leave this or t-enclosure blank to not show link to enclosures -->
	<xsl:variable name="t-enclosure">enclosure</xsl:variable> <!-- text of untitled enclosures; leave this or t-download blank to not show link to enclosures -->
	<!-- END SETTINGS -->

	
	<xsl:template match="/">
		<!-- <xsl:comment>For information about the XSLT file that generated this, see http://opensearch.a9.com/docs/stylesheet.jsp</xsl:comment> -->
		<xsl:choose>
			<xsl:when test="not(atom:feed | rss/channel | //rss1:item | //rss9:item)">
				<html xml:lang="{$t-lang}" lang="{$t-lang}">
					<head>
						<title><xsl:value-of select="$t-errortitle" /></title>
						<meta name="robots" content="noindex,nofollow,noarchive" />
					</head>
					<body><p><xsl:value-of select="$t-errordesc" /></p></body>
				</html>
			</xsl:when>
			<xsl:otherwise><xsl:apply-templates /></xsl:otherwise>
		</xsl:choose>
	</xsl:template>

	<xsl:template match="atom:feed | rss/channel | rdf:RDF">
		<xsl:variable name="language" select="(@xml:lang | language)[1]" />
		<html xml:lang="{$language}" lang="{$language}">
			<xsl:variable name="query" select="opensearch:Query[@role='request' and @searchTerms][1]/@searchTerms" />
			<xsl:variable name="statedtitle" select="(atom:title | title | //rss1:channel/rss1:title | //rss9:channel/rss9:title)[1]" />
			<xsl:variable name="title">
				<xsl:choose>
					<xsl:when test="string-length($statedtitle)&gt;0 and (not(string-length($query)&gt;0) or contains($statedtitle, $query))"><xsl:value-of select="$statedtitle" /></xsl:when>
					<xsl:when test="string-length($statedtitle)&gt;0 and string-length($query)&gt;0"><xsl:value-of select="$statedtitle" /> (<xsl:value-of select="$query" />)</xsl:when>
					<xsl:when test="string-length($query)&gt;0"><xsl:value-of select="$t-resultsfor" /> '<xsl:value-of select="$query" />'</xsl:when>
					<xsl:otherwise><xsl:value-of select="$t-resultstitle" /></xsl:otherwise>
				</xsl:choose>
			</xsl:variable>
			<!-- search stats and rel links -->
			<xsl:variable name="items" select="atom:entry | item | //rss1:item | //rss9:item" />
			<xsl:variable name="endIndex">
				<xsl:choose>
					<xsl:when test="opensearch:startIndex | opensearchOld:startIndex"><xsl:value-of select="(opensearch:startIndex | opensearchOld:startIndex)[1] + count($items) - 1" /></xsl:when>
					<xsl:otherwise><xsl:value-of select="count($items)" /></xsl:otherwise>
				</xsl:choose>
			</xsl:variable>
			<xsl:variable name="totalresults"><xsl:if test="(opensearch:totalResults | opensearchOld:totalResults)&gt;=$endIndex"><xsl:value-of select="(opensearch:totalResults | opensearchOld:totalResults)[1]" /></xsl:if></xsl:variable>
			<xsl:variable name="navprev"><xsl:if test="atom:link[@rel='previous']/@href and ((opensearch:startIndex&gt;1 or opensearchOld:startIndex&gt;1) or not(opensearch:startIndex or opensearchOld:startIndex))"><xsl:call-template name="resolvelink"><xsl:with-param name="url" select="(atom:link[@rel='previous']/@href)[1]" /></xsl:call-template></xsl:if></xsl:variable>
			<xsl:variable name="navnext"><xsl:if test="atom:link[@rel='next']/@href and (($totalresults&gt;0 and $totalresults&gt;$endIndex) or (not($totalresults&gt;0)))"><xsl:call-template name="resolvelink"><xsl:with-param name="url" select="atom:link[@rel='next']/@href" /></xsl:call-template></xsl:if></xsl:variable>

			<xsl:variable name="statedStartIndex" select="(opensearch:startIndex | opensearchOld:startIndex)[1]" />
			<head>
				<title><xsl:value-of select="$title" /></title>
				<meta name="robots" content="noindex,follow,noarchive" />
				<xsl:if test="atom:icon">
					<xsl:variable name="iconurl"><xsl:call-template name="resolvelink"><xsl:with-param name="url" select="atom:icon[1]" /></xsl:call-template></xsl:variable>
					<link rel="shortcut icon" href="{$iconurl}" />
				</xsl:if>
				<link rel="stylesheet" type="text/css" title="default" media="screen">
					<xsl:attribute name="href"><xsl:value-of select="concat($base_dir,'os.css')"/></xsl:attribute>
				</link>
				<!-- rel links -->

				<xsl:for-each select="atom:link[@rel='unapi' and string-length(@href)&gt;0]">
					<link rel="unapi-server" title="unAPI" type="application/xml">
						<xsl:attribute name='href'>
							<xsl:value-of select="@href"/>
						</xsl:attribute>
					</link>
				</xsl:for-each>

				<xsl:if test="string-length($navprev)&gt;0"><link rel="previous" href="{$navprev}" title="{$t-prevpage}" /></xsl:if>
				<xsl:if test="string-length($navnext)&gt;0"><link rel="next" href="{$navnext}" title="{$t-nextpage}" /></xsl:if>
				<xsl:if test="atom:link[@rel='first']/@href and ($statedStartIndex&gt;1 or string-length($statedStartIndex)=0)">
					<xsl:variable name="starturl"><xsl:call-template name="resolvelink"><xsl:with-param name="url" select="(atom:link[@rel='first']/@href)[1]" /></xsl:call-template></xsl:variable>
					<link rel="start" title="{$t-firstpage}" href="{$starturl}" />
				</xsl:if>
				<xsl:if test="atom:link[@rel='last']/@href and ($totalresults&gt;$endIndex or string-length($totalresults)=0)">
					<xsl:variable name="endurl"><xsl:call-template name="resolvelink"><xsl:with-param name="url" select="(atom:link[@rel='last']/@href)[1]" /></xsl:call-template></xsl:variable>
					<link rel="last" title="{$t-lastpage}" href="{$endurl}"/>
				</xsl:if>
				<xsl:for-each select="atom:link[(@rel='alternate' or @rel='self' or @rel='description') and @href]">
					<xsl:variable name="linkurl"><xsl:call-template name="resolvelink"><xsl:with-param name="url" select="@href" /></xsl:call-template></xsl:variable>
					<link rel="{@rel}" href="{$linkurl}" hreflang="{@hreflang}" title="{@title}" type="{@type}"/>
				</xsl:for-each>
			</head>
			<body>

				<!-- title section -->
				<div id="header">


					<xsl:variable name="htmllink" select="(atom:link[@rel='alternate' or not(@rel)]/@href | link | rss1:link)[1]" />
					<h1>
						<!--
						<xsl:choose>
							<xsl:when test="$htmllink">
								<xsl:variable name="htmlversion"><xsl:if test="$htmllink"><xsl:call-template name="resolvelink"><xsl:with-param name="url" select="$htmllink" /></xsl:call-template></xsl:if></xsl:variable>
								<a href="{$htmlversion}"><xsl:value-of select="$title" /></a>
							</xsl:when>
							<xsl:otherwise><xsl:value-of select="$title" /></xsl:otherwise>
						</xsl:choose>
						-->
						<xsl:value-of select="$title" />
					</h1>
 					<xsl:variable name="imgurl" select="(atom:logo | image/url | rss1:image/rss1:url | rss9:image/rss9:url)[1]" />
 					<xsl:variable name="absimgurl"><xsl:if test="$imgurl"><xsl:call-template name="resolvelink"><xsl:with-param name="url" select="$imgurl" /></xsl:call-template></xsl:if></xsl:variable>
 					<xsl:if test="$absimgurl"><img src="{$absimgurl}" width="{image/width}" height="{image/height}" alt="{image/title}" /></xsl:if>
					<xsl:variable name="subtitle" select="(atom:subtitle | description | //rss1:channel/rss1:description | //rss9:channel/rss9:description)[1]" />
					<xsl:if test="$subtitle and ($subtitle != $title)"><p><xsl:value-of select="$subtitle" /></p></xsl:if>
					<!--<xsl:if test="$t-authors and (managingEditor | atom:author | dc:creator | dc:publisher | atom:contributor | dc:contributor)"><p><xsl:value-of select="concat($t-authors,' ')" /><xsl:apply-templates select="managingEditor | atom:author | dc:creator | dc:publisher | atom:contributor | dc:contributor" /></p></xsl:if> -->
					<xsl:if test="$t-categories and (atom:category | category)"><xsl:value-of select="concat($t-categories, ' ')" /><p><xsl:apply-templates select="atom:category | category" /></p></xsl:if>
				</div>

				<div id="searchdiv">
					<form method="GET">
						<xsl:attribute name="action"><xsl:value-of select="concat($base_dir, 'opensearch/1.1/', $lib, '/html-full')" /></xsl:attribute>
						<b>Search:</b>
						<input class="searchbox" type="text" name="searchTerms" value="{$searchTerms}"/>
						<select name="searchClass">
							<option value="keyword">
								<xsl:if test="$searchClass = 'keyword'">
									<xsl:attribute name="selected"><xsl:value-of select="1"/></xsl:attribute>
								</xsl:if>
								<xsl:text>Keyword</xsl:text>
							</option>
							<option value="title">
								<xsl:if test="$searchClass = 'title'">
									<xsl:attribute name="selected"><xsl:value-of select="1"/></xsl:attribute>
								</xsl:if>
								<xsl:text>Title</xsl:text>
							</option>
							<option value="author">
								<xsl:if test="$searchClass = 'author'">
									<xsl:attribute name="selected"><xsl:value-of select="1"/></xsl:attribute>
								</xsl:if>
								<xsl:text>Author</xsl:text>
							</option>
							<option value="subject">
								<xsl:if test="$searchClass = 'subject'">
									<xsl:attribute name="selected"><xsl:value-of select="1"/></xsl:attribute>
								</xsl:if>
								<xsl:text>Subject</xsl:text>
							</option>
							<option value="series">
								<xsl:if test="$searchClass = 'series'">
									<xsl:attribute name="selected"><xsl:value-of select="1"/></xsl:attribute>
								</xsl:if>
								<xsl:text>Series</xsl:text>
							</option>
						</select>
						<input type="submit" value="Go!"/>
					</form>
					<br/>
				</div>
				
				<!-- text input: if present in an opensearch feed, this is probably a search box -->
				<xsl:if test="textInput | rss1:textinput"><xsl:apply-templates select="(textInput | rss1:textinput)[1]"><xsl:with-param name="query" select="$query" /></xsl:apply-templates></xsl:if>

				<!-- output search results or 'no results' msg -->
				<xsl:choose>
					<xsl:when test="$items">
						<!-- display the search numbers -->
						<p class="nav">
							<xsl:value-of select="concat($t-results,' ')" />
							<xsl:choose>
								<xsl:when test="$statedStartIndex&gt;0"><xsl:value-of select="$statedStartIndex" /></xsl:when>
								<xsl:otherwise>1</xsl:otherwise>
							</xsl:choose>
							<xsl:value-of select="concat(' ', $t-resultsto, ' ')" />
							<xsl:value-of select="$endIndex" />
							<xsl:if test="$totalresults&gt;0"><xsl:value-of select="concat(' ', $t-resultsof, ' ')" /><xsl:number value="$totalresults" grouping-size="3" grouping-separator="," /></xsl:if>
							<xsl:if test="string-length($navnext)&gt;0 or string-length($navprev)&gt;0">   |   </xsl:if>
							<xsl:if test="string-length($navprev)&gt;0">
								<a class="x-escape" href="{$navprev}" rel="previous"><xsl:value-of select="$t-prevlink" disable-output-escaping="yes" /></a>
								<xsl:if test="string-length($navnext)&gt;0"> | </xsl:if>
							</xsl:if>
							<xsl:if test="string-length($navnext)&gt;0"><a class="x-escape" href="{$navnext}" rel="next"><xsl:value-of select="$t-nextlink" disable-output-escaping="yes" /></a></xsl:if>
						</p>
						<dl><xsl:apply-templates select="$items" /></dl>
						<!-- result navigation -->
						<p class="nav">
							<xsl:value-of select="concat($t-results,' ')" />
							<xsl:choose>
								<xsl:when test="$statedStartIndex&gt;0"><xsl:value-of select="$statedStartIndex" /></xsl:when>
								<xsl:otherwise>1</xsl:otherwise>
							</xsl:choose>
							<xsl:value-of select="concat(' ', $t-resultsto, ' ')" />
							<xsl:value-of select="$endIndex" />
							<xsl:if test="$totalresults&gt;0"><xsl:value-of select="concat(' ', $t-resultsof, ' ')" /><xsl:number value="$totalresults" grouping-size="3" grouping-separator="," /></xsl:if>
							<xsl:if test="string-length($navnext)&gt;0 or string-length($navprev)&gt;0">   |   </xsl:if>
							<xsl:if test="string-length($navprev)&gt;0">
								<a class="x-escape" href="{$navprev}" rel="previous"><xsl:value-of select="$t-prevlink" disable-output-escaping="yes" /></a>
								<xsl:if test="string-length($navnext)&gt;0"> | </xsl:if>
							</xsl:if>
							<xsl:if test="string-length($navnext)&gt;0"><a class="x-escape" href="{$navnext}" rel="next"><xsl:value-of select="$t-nextlink" disable-output-escaping="yes" /></a></xsl:if>
						</p>
					</xsl:when>
					<xsl:when test="(opensearch:startIndex&gt;1 or opensearchOld&gt;1) and not($totalresults=0)"><xsl:value-of select="$t-nomoreresults" /></xsl:when>
					<xsl:otherwise><!-- <p><xsl:value-of select="$t-noresults" /></p> --></xsl:otherwise>
				</xsl:choose>

				<!-- display the copyright -->
				<xsl:variable name="rights" select="(atom:rights[not(@type) or @type='' or @type='text' or @type='html' or @type='xhtml'] | copyright | dc:rights)[1]" />
				<div id="footer">
					<xsl:if test="$rights"><p><xsl:call-template name="showtext"><xsl:with-param name="node" select="$rights" /></xsl:call-template></p></xsl:if>
					<p><small>This XSLT is &#169; <a href="http://a9.com/">A9.com, Inc</a>; see <a href="http://opensearch.a9.com/docs/stylesheet.jsp">full details</a>.</small></p>
				</div>

			</body>
		</html>
	</xsl:template>
	
	<xsl:template match="textInput | rss1:textinput">
		<xsl:param name="query" />
		<xsl:if test="(name | rss1:name) and (link | rss1:link)">
			<xsl:variable name="formaction"><xsl:call-template name="resolvelink"><xsl:with-param name="url" select="(link | rss1:link)[1]" /></xsl:call-template></xsl:variable>
			<form method="get" action="{$formaction}">
				<input type="text" name="{name | rss1:name}" value="{$query}" />
				<xsl:choose>
					<xsl:when test="title | rss1:title"><input type="submit" value="{title | rss1:title}" /></xsl:when>
					<xsl:otherwise><input type="submit" /></xsl:otherwise>
				</xsl:choose>
				<xsl:if test="description | rss1:description"><p><xsl:value-of select="(description | rss1:description)[1]" /></p></xsl:if>
			</form>
		</xsl:if>
	</xsl:template>

	<xsl:template match="dc:identifier">
		<xsl:attribute name="src">
			<xsl:choose>
				<xsl:when test="position() &lt; 2 and string-length(.) &gt; 9">
					<xsl:variable name="isbnraw"><xsl:value-of select="substring-after(.,'ISBN:')"/></xsl:variable>
					<xsl:choose>
						<xsl:when test="substring-before($isbnraw,' ')">
							<xsl:variable name="isbntrimmed"><xsl:value-of select="substring-before($isbnraw,' ')"/></xsl:variable>
							<xsl:value-of select="concat('/opac/jackets/',$isbntrimmed)"/>
						</xsl:when>
						<xsl:otherwise>
							<xsl:value-of select="concat('/opac/jackets/',$isbnraw)"/>
						</xsl:otherwise>
					</xsl:choose>
				</xsl:when>
				<xsl:otherwise>
					<xsl:value-of select="concat('/opac/jackets/','---')"/>
				</xsl:otherwise>
			</xsl:choose>
		</xsl:attribute>		
	</xsl:template>

	<xsl:template match="atom:entry | item | //rss1:item | //rss9:item"> <!-- match="" must match the select="" earlier on -->
		<xsl:variable name="url"><xsl:call-template name="resolvelink"><xsl:with-param name="url" select="(atom:link[not(@rel) or @rel='alternate' or @rel='']/@href | link | guid[@isPermaLink='true'] | rss1:link | rss9:link)[1]" /></xsl:call-template></xsl:variable>
		<!-- item title -->
		<dt>
			<xsl:choose>
				<xsl:when test="string-length($url)&gt;0">
					<a href="{$url}">
						<xsl:choose>
							<xsl:when test="atom:title | title | rss1:title | rss9:title"><xsl:call-template name="showtext"><xsl:with-param name="node" select="(atom:title | title | rss1:title | rss9:title)[1]" /></xsl:call-template></xsl:when>
							<xsl:otherwise><xsl:value-of select="$t-untitleditem" /></xsl:otherwise>
						</xsl:choose>
					</a>
				</xsl:when>
				<xsl:otherwise>
					<strong>
						<xsl:choose>
							<xsl:when test="atom:title | title | rss1:title | rss9:title"><xsl:call-template name="showtext"><xsl:with-param name="node" select="(atom:title | title | rss1:title | rss9:title)[1]" /></xsl:call-template></xsl:when>
							<xsl:otherwise><xsl:value-of select="$t-untitleditem" /></xsl:otherwise>
						</xsl:choose>
					</strong>
				</xsl:otherwise>
			</xsl:choose>
			<!-- item authors -->
			<xsl:if test="$t-authors and (author | atom:author | atom:contributor | dc:creator | dc:publisher | dc:contributor)">
				<xsl:value-of select="concat(' ', $t-authors, ' ')" />
				<xsl:apply-templates select="author | atom:author | atom:contributor | dc:creator | dc:publisher | dc:contributor" />
			</xsl:if>
		</dt>
		<!-- item description -->
		<xsl:if test="atom:content[not(@type) or @type='' or @type='text' or @type='html' or @type='xhtml'] | content:encoded | description | rss1:description | rss9:description | atom:summary[not(@type) or @type='' or @type='text' or @type='html' or @type='xhtml']">
			<dd class="desc">
				<xsl:if test="string-length($url)&gt;0">
					<a href="{$url}" style="text-decoration: none;">
						<img align="left" style="margin:5px; border: 0px;" height="50" width="40">
							<xsl:apply-templates select="dc:identifier"/>
						</img>
					</a>
				</xsl:if>
				<xsl:choose>
					<xsl:when test="atom:content[(not(@type) or @type='' or @type='text' or @type='html' or @type='xhtml') and not(@src)] | content:encoded"><xsl:call-template name="showtext"><xsl:with-param name="node" select="atom:content[(not(@type) or @type='' or @type='text' or @type='html' or @type='xhtml') and not(@src)] | content:encoded" /></xsl:call-template></xsl:when>
					<xsl:when test="description | rss1:description | rss9:description | atom:summary[not(@type) or @type='' or @type='text' or @type='html' or @type='xhtml']"><xsl:call-template name="showtext"><xsl:with-param name="node" select="description | rss1:description | rss9:description | atom:summary[not(@type) or @type='' or @type='text' or @type='html' or @type='xhtml']" /></xsl:call-template></xsl:when>
				</xsl:choose>
				<xsl:if test="atom:content/@src">
					<xsl:if test="atom:summary"><br /></xsl:if>
					<a>
						<xsl:attribute name="href"><xsl:call-template name="resolvelink"><xsl:with-param name="url" select="atom:content/@src" /></xsl:call-template></xsl:attribute>
						<xsl:value-of select="$t-entrylink" />
					</a>
				</xsl:if>
			</dd>
		</xsl:if>
		<!-- item categories -->
		<xsl:if test="$t-categories and (atom:category | category)"><dd><xsl:value-of select="concat($t-categories, ' ')" /><xsl:apply-templates select="atom:category | category" /></dd></xsl:if>
		<!-- item source -->
		<xsl:if test="string-length($t-source)&gt;0">
			<xsl:variable name="maybesourceurl" select="(atom:source/link[@rel='alternate']/@href | source/@url)[1]" />
			<xsl:variable name="sourceurl"><xsl:if test="$maybesourceurl"><xsl:call-template name="resolvelink"><xsl:with-param name="url" select="$maybesourceurl" /></xsl:call-template></xsl:if></xsl:variable>
			<xsl:variable name="maybesourcename">
				<xsl:choose>
					<xsl:when test="atom:source/title[not(@type) or @type='' or @type='text' or @type='html' or @type='xhtml']"><xsl:value-of select="atom:source/title[@type='' or @type='text' or @type='html' or @type='xhtml'][1]" /></xsl:when>
					<xsl:when test="string-length(source)&gt;0"><xsl:value-of select="source[1]" /></xsl:when>
					</xsl:choose>
			</xsl:variable>
			<xsl:if test="string-length($sourceurl)&gt;0 or string-length($maybesourcename)&gt;0">
				<dd>
					<xsl:value-of select="concat($t-source,' ')" />
					<xsl:variable name="sourcename">
						<xsl:choose>
							<xsl:when test="$maybesourcename"><xsl:value-of select="$maybesourcename" /></xsl:when>
							<xsl:otherwise><xsl:value-of select="$sourceurl" /></xsl:otherwise>
						</xsl:choose>
					</xsl:variable>
					<xsl:choose>
						<xsl:when test="$sourceurl"><a href="{$sourceurl}"><xsl:value-of select="$sourcename" /></a></xsl:when>
						<xsl:otherwise><xsl:value-of select="$sourcename" /></xsl:otherwise>
					</xsl:choose>
				</dd>
			</xsl:if>
		</xsl:if>
		<!-- item comments -->
		<xsl:if test="comments and string-length($t-comments)&gt;0">
			<xsl:variable name="commentsurl"><xsl:call-template name="resolvelink"><xsl:with-param name="url" select="comments[1]" /></xsl:call-template></xsl:variable>
			<dd><a href="{$commentsurl}"><xsl:value-of select="$t-comments" /></a></dd>
		</xsl:if>
		<!-- item enclosure -->
		<xsl:if test="(atom:link[@rel='enclosure']/@href | enclosure/@url) and string-length($t-download)&gt;0 and string-length($t-enclosure)&gt;0"><dd><xsl:apply-templates select="atom:link[@rel='enclosure'] | enclosure" /></dd></xsl:if>
		<!-- item rights -->
		<xsl:variable name="itemrights" select="atom:rights[not(@type) or @type='' or @type='text' or @type='html' or @type='xhtml'][1]" />
		<xsl:if test="$itemrights"><dd class="rights"><xsl:call-template name="showtext"><xsl:with-param name="node" select="$itemrights" /></xsl:call-template></dd></xsl:if>
		<!-- item url -->
		<xsl:if test="string-length($url)&gt;0">
			<dd class="url">
				<abbr class="unapi-id">
					<xsl:for-each select="atom:link[@rel='unapi-id']">
						<xsl:attribute name="title">
							<xsl:value-of select="@href" />
						</xsl:attribute>
					</xsl:for-each>
					<xsl:choose>
						<xsl:when test="string-length(substring-after($url, 'http://'))&gt;100">
							<xsl:value-of select="concat(substring(substring-after($url, 'http://'),1,100),'&#8230;')" />
						</xsl:when>
						<xsl:otherwise>
							<xsl:value-of select="substring-after($url, 'http://')" />
						</xsl:otherwise>
					</xsl:choose>
				</abbr>
			</dd>
		</xsl:if>
		<br clear="all"/>
	</xsl:template>

	<xsl:template match="atom:link[@rel='enclosure'] | enclosure">
		<xsl:variable name="encurl"><xsl:call-template name="resolvelink"><xsl:with-param name="url" select="(@href | @url)[1]" /></xsl:call-template></xsl:variable>
		<xsl:value-of select="concat($t-download, ' ')" />
		<a href="{$encurl}">
			<xsl:choose>
				<xsl:when test="@title"><xsl:value-of select="@title" /></xsl:when>
				<xsl:otherwise><xsl:value-of select="$t-enclosure" /></xsl:otherwise>
			</xsl:choose>
		</a>
		<xsl:if test="@type"> (<xsl:value-of select="@type" />)</xsl:if>
	</xsl:template>

	<xsl:template match="atom:category | category">
		<xsl:variable name="name">
			<xsl:choose>
				<xsl:when test="not(namespace-uri())"><xsl:value-of select="." /></xsl:when>
				<xsl:when test="@label"><xsl:value-of select="@label" /></xsl:when>
				<xsl:when test="@term"><xsl:value-of select="@term" /></xsl:when>
			</xsl:choose>
		</xsl:variable>
		<xsl:if test="string-length($name)&gt;0">
			<xsl:variable name="category">
				<xsl:choose>
					<xsl:when test="not(namespace-uri())"><xsl:value-of select="." /></xsl:when>
					<xsl:otherwise><xsl:value-of select="@term" /></xsl:otherwise>
				</xsl:choose>
			</xsl:variable>
			<xsl:variable name="maybeurl" select="(@domain | @scheme)[1]" />
			<xsl:variable name="url">
				<xsl:choose>
					<xsl:when test="starts-with($maybeurl, 'http')">
						<xsl:value-of select="concat($maybeurl, '#', $category)" />
					</xsl:when>
					<xsl:otherwise>
						<xsl:value-of select="concat($base_dir, 'opensearch/1.1/', $lib, '/html-full/subject?searchTerms=', $name)" />
					</xsl:otherwise>
				</xsl:choose>
			</xsl:variable>
			<xsl:choose>
				<xsl:when test="string-length($url)&gt;0"><a href="{$url}"><xsl:value-of select="$name" /></a></xsl:when>
				<xsl:otherwise><xsl:value-of select="$name" /></xsl:otherwise>
			</xsl:choose>
			<xsl:text>; </xsl:text>
		</xsl:if>
	</xsl:template>
	
	<!-- outputs a 'person' (next 4 templates) -->
	<xsl:template match="dc:creator | dc:publisher | dc:contributor">
		<xsl:call-template name="person"><xsl:with-param name="name" select="." /></xsl:call-template>
	</xsl:template>
	<xsl:template match="managingEditor | webMaster | author">
		<xsl:call-template name="person">
			<xsl:with-param name="email" select="substring-before(concat(normalize-space(.),' '), ' ')" />
			<xsl:with-param name="name"><xsl:if test="substring-after(., '(')"><xsl:value-of select="normalize-space(substring-before(substring-after(., '('), ')'))" /></xsl:if></xsl:with-param>
		</xsl:call-template>
	</xsl:template>
	<xsl:template match="atom:author | atom:contributor">
		<xsl:call-template name="person">
			<xsl:with-param name="link"><xsl:if test="atom:uri"><xsl:call-template name="resolvelink"><xsl:with-param name="url" select="atom:uri" /></xsl:call-template></xsl:if></xsl:with-param>
			<xsl:with-param name="email" select="atom:email" />
			<xsl:with-param name="name" select="atom:name" />
		</xsl:call-template>
	</xsl:template>
	<xsl:template name="person">
		<xsl:param name="email" />
		<xsl:param name="link" />
		<xsl:param name="name" />
		<xsl:variable name="showname">
			<xsl:choose>
				<xsl:when test="string-length($name)&gt;0"><xsl:value-of select="$name" /></xsl:when>
				<xsl:when test="string-length($email)&gt;0"><xsl:value-of select="$email" /></xsl:when>
				<xsl:otherwise><xsl:value-of select="$link" /></xsl:otherwise>
			</xsl:choose>
		</xsl:variable>
		<xsl:variable name="showlink">
			<xsl:choose>
				<xsl:when test="string-length($link)"><xsl:value-of select="$link" /></xsl:when>
				<xsl:when test="string-length($email)">mailto:<xsl:value-of select="$email" /></xsl:when>
			</xsl:choose>
		</xsl:variable>
		<xsl:if test="string-length($showname)&gt;0">
			<xsl:choose>
				<xsl:when test="string-length($showlink)&gt;0"><a href="{$showlink}"><xsl:value-of select="$showname" /></a></xsl:when>
				<xsl:otherwise>
					<a>
						<xsl:attribute name="href">
							<xsl:value-of select="concat($base_dir, 'opensearch/1.1/', $lib, '/html-full/author?searchTerms=', $showname)" />
						</xsl:attribute>
						<xsl:value-of select="$showname" />
					</a>
				</xsl:otherwise>
			</xsl:choose>
			<xsl:text>; </xsl:text>
		</xsl:if>
	</xsl:template>
	
	<!-- outputs text/(x)html; based on code from jtesler -->
	<xsl:template name="showtext">
		<xsl:param name="node" />
		<xsl:choose>
			<xsl:when test="name($node)='description' or $node/@type='html'"><div class="x-escape"><xsl:value-of select="$node" disable-output-escaping="yes" /></div></xsl:when>
			<xsl:when test="$node/@type='xhtml'"><xsl:apply-templates select="$node/xhtml:div" mode="stripXhtml" /></xsl:when>
			<xsl:otherwise><xsl:value-of select="$node" /></xsl:otherwise>
		</xsl:choose>
	</xsl:template>
	<!-- These templates are used for outputting the xhtml output.  We need to
	Strip xhtml: from all the nodes.  We must also convert any href and src
	attributes from relative to absolute if there is an xml:base -->
	<xsl:template match="xhtml:*" mode="stripXhtml">
		<xsl:element name="{local-name()}">
			<xsl:if test="@href"><xsl:attribute name="href"><xsl:call-template name="resolvelink"><xsl:with-param name="url" select="@href"/></xsl:call-template></xsl:attribute></xsl:if>
			<xsl:if test="@src"><xsl:attribute name="src"><xsl:call-template name="resolvelink"><xsl:with-param name="url" select="@src"/></xsl:call-template></xsl:attribute></xsl:if>
			<xsl:apply-templates select="@* | node()" mode="stripXhtml" />
		</xsl:element>
	</xsl:template>
	<xsl:template match="node() | @*" mode="stripXhtml"><xsl:copy><xsl:apply-templates select="@* | node()" mode="stripXhtml" /></xsl:copy></xsl:template>
	<!-- Since we already processed href and src nodes up above, don't process them again here -->
	<xsl:template match="@href | @src" mode="stripXhtml" priority="1" />
	
	<!-- returns absolute links, given absolute ones or relative ones with base ones -->
	<xsl:template name="resolvelink">
		<xsl:param name="url" />
		<xsl:param name="node" select="$url" />
		<xsl:choose>
			<xsl:when test="(contains($url,':') and (not(contains($url,'/')) or contains(substring-before($url,':'), substring-before($url,':')))) or not($url)"><xsl:value-of select="$url" /></xsl:when><!-- url is absolute already -->
			<xsl:otherwise>
				<xsl:variable name="basenode" select="($node/ancestor-or-self::*[@xml:base])[last()]" />
				<xsl:variable name="base">
						<xsl:call-template name="resolvelink">
						<xsl:with-param name="url" select="$basenode/@xml:base" />
						<xsl:with-param name="node" select="($basenode/ancestor::*[@xml:base])[last()]" />
					</xsl:call-template>
				</xsl:variable>
				<xsl:variable name="protocol"><xsl:if test="contains($base, '://')"><xsl:value-of select="concat(substring-before($base, '://'), '://')" /></xsl:if></xsl:variable>
				<xsl:variable name="basenoprot"><xsl:choose><xsl:when test="string-length($protocol)"><xsl:value-of select="substring-after($base, '://')" /></xsl:when><xsl:otherwise><xsl:value-of select="$base" /></xsl:otherwise></xsl:choose></xsl:variable>
				<xsl:variable name="trailingslash"><xsl:if test="substring($basenoprot,string-length($basenoprot),1)='/'">true</xsl:if></xsl:variable>
				<xsl:variable name="usebase">
					<xsl:value-of select="$protocol" />
					<xsl:choose>
						<xsl:when test="not(string-length($trailingslash)) and not(contains($basenoprot, '/'))"><xsl:value-of select="$basenoprot" />/</xsl:when>
						<xsl:when test="not(string-length($trailingslash)) and contains($basenoprot, '/') and $url != '' and not(starts-with($url, '#')) and not(starts-with($url, '?'))">
							<xsl:call-template name="uponelevel">
								<xsl:with-param name="url" select="$basenoprot" />
							</xsl:call-template>
						</xsl:when>
						<xsl:otherwise><xsl:value-of select="$basenoprot" /></xsl:otherwise>
					</xsl:choose>
				</xsl:variable>
				<xsl:choose>
					<xsl:when test="starts-with($url,'/')"><xsl:value-of select="concat(substring-before($base, '://'), '://', substring-before(substring-after($usebase, '://'), '/'), $url)" /></xsl:when>
					<xsl:when test="starts-with($url,'../')">
						<xsl:call-template name="resolvelink">
							<xsl:with-param name="url" select="substring-after($url, '../')" />
							<xsl:with-param name="base">
								<xsl:value-of select="concat(substring-before($base,'://'), '://')" />
								<xsl:call-template name="uponelevel"><xsl:with-param name="url" select="substring-after(substring($usebase, 0, string-length($usebase)-1), '://')" /></xsl:call-template>
							</xsl:with-param>
						</xsl:call-template>
					</xsl:when>
					<xsl:otherwise>
						<xsl:variable name="useurl">
							<xsl:choose>
								<xsl:when test="starts-with($url, './')"><xsl:value-of select="substring-after($url, './')" /></xsl:when>
								<xsl:otherwise><xsl:value-of select="$url" /></xsl:otherwise>
							</xsl:choose>
						</xsl:variable>
						<xsl:value-of select="concat($usebase, $useurl)" />
					</xsl:otherwise>
				</xsl:choose>
			</xsl:otherwise>
		</xsl:choose>
	</xsl:template>
	<xsl:template name="uponelevel">
		<xsl:param name="url" /> <!-- url looks like sub.domain.com/folder/two/three -->
		<xsl:variable name="firstpart" select="substring-before($url, '/')" />
		<xsl:variable name="afterslash" select="substring-after($url, '/')" />
		<xsl:variable name="secondpart"><xsl:if test="contains($afterslash, '/')"><xsl:call-template name="uponelevel"><xsl:with-param name="url" select="$afterslash" /></xsl:call-template></xsl:if></xsl:variable>
		<xsl:value-of select="concat($firstpart, '/', $secondpart)" />
	</xsl:template>

</xsl:stylesheet>
