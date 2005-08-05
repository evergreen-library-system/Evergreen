#include "xmltools.h"

#define TEXT_DTD "test2.dtd"



/*
int main( int argc, char* argv[] ) {

	char* file = argv[1];
	char* localedir = argv[2];

	int len = strlen(TEXT_DTD) + strlen(localedir) + 1;
	char dtdfile[len];
	bzero(dtdfile, len);

	if(localedir)
		sprintf(dtdfile, "%s/%s",  localedir, TEXT_DTD );


	if(access(dtdfile, R_OK)) {
		fprintf(stderr, "Unable to open DTD file %s\n", dtdfile);
		fflush(stderr);
		return HTTP_INTERNAL_SERVER_ERROR;
	}


	xmlDocPtr doc;

	xmlSubstituteEntitiesDefault(0);


	if( (doc = xmlParseFile(file)) == NULL) {
		fprintf(stderr, "\n ^-- Error parsing XML file %s\n", file);
		fflush(stderr);
		return HTTP_INTERNAL_SERVER_ERROR;
	}

	if( xmlXIncludeProcess(doc) < 0 ) {
		fprintf(stderr, "\n ^-- Error processing XIncludes for file %s\n", file);
		fflush(stderr);
		return HTTP_INTERNAL_SERVER_ERROR;
	}

	xmlReplaceDtd(doc, dtdfile);

	doc = xmlProcessDtdEntities(doc);

	char* xml = xmlDocToString(doc, 0);

	printf("\n%s\n", xml);

	free(xml);
	xmlFreeDoc(doc);
	xmlCleanupCharEncodingHandlers();
	xmlCleanupParser();

	return 0;

}
*/

xmlDocPtr xmlProcessDtdEntities(xmlDocPtr doc) {
	char* xml = xmlDocToString(doc, 1);
	xmlFreeDoc(doc);
	xmlSubstituteEntitiesDefault(1);
	xmlDocPtr d = xmlParseMemory(xml, strlen(xml));
	free(xml);
	return d;
}


int xmlReplaceDtd(xmlDocPtr doc, char* dtdfile) {

	if(!doc || !dtdfile) return 0;

	/* remove the original DTD */
	if(doc->children && doc->children->type ==  XML_DTD_NODE) {
		xmlNodePtr p = doc->children;
		xmlUnlinkNode(p);
		xmlFreeNode(p);
	}


	xmlDtdPtr dtd = xmlParseDTD(NULL, dtdfile);

	if(!dtd) {
		fprintf(stderr, "Error parsing DTD file %s\n", dtdfile);
		fflush(stderr);
		return -1;
	}

	fprintf(stderr, "2\n");
	fflush(stderr);

	dtd->name = xmlStrdup((xmlChar*)"x");
	doc->extSubset = dtd;	
	dtd->doc = doc;
	dtd->parent = doc;
	xmlNodePtr x = doc->children;
	doc->children = (xmlNodePtr)dtd;
	dtd->next = x;

	return 1;
}

char* xmlDocToString(xmlDocPtr doc, int full) {

	char* xml;

	if(full) {

		xmlChar* xmlbuf;
		int size;
		xmlDocDumpMemory(doc, &xmlbuf, &size);
		xml = strdup((char*) (xmlbuf));
		xmlFree(xmlbuf);
		return xml;

	} else {

		xmlBufferPtr xmlbuf = xmlBufferCreate();
		xmlNodeDump( xmlbuf, doc, xmlDocGetRootElement(doc), 0, 0);
		xml = strdup((char*) (xmlBufferContent(xmlbuf)));
		xmlBufferFree(xmlbuf);
		return xml;

	}

}
