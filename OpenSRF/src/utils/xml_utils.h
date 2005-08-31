#ifndef _XML_UTILS_H
#define _XML_UTILS_H

#include "objson/object.h"
#include <libxml/parser.h>
#include <libxml/tree.h>

jsonObject* xmlDocToJSON(xmlDocPtr doc);

/* helper function */
jsonObject* _xmlToJSON(xmlNodePtr node, jsonObject*);

/* debug function, prints each node and content */
void recurse_doc( xmlNodePtr node );


/* turns an XML doc into a char*.  
	User is responsible for freeing the returned char*
	if(full), then we return the whole doc (xml declaration, etc.)
	else we return the doc from the root node down
	*/
char* xmlDocToString(xmlDocPtr doc, int full);

#endif
