
/* general headers */
#include <stdio.h>
#include <string.h>
#include <strings.h>

/* libxml2 headers */
#include <libxml/parser.h>
#include <libxml/globals.h>
#include <libxml/xinclude.h>
#include <libxml/xmlwriter.h>
#include <libxml/xmlreader.h>


#ifndef XMLTOOLS_H
#define XMLTOOLS_H


/* turns a doc into a string.  string must be deallocated.
	if 'full', then the entire doc is stringified, otherwise
	the root node (on down) is stringified */
char* xmlDocToString(xmlDocPtr doc, int full);

int xmlReplaceDtd(xmlDocPtr doc, char* dtdfile);

/* Inline DTD Entity replacement.
	creates a new doc with the entities replaced, frees the
	doc provided and returns a new one.  
	Do this and you'll be OK:
		doc = xmlProcessDtdEntities(doc);
		*/
xmlDocPtr xmlProcessDtdEntities(xmlDocPtr doc);


#endif


