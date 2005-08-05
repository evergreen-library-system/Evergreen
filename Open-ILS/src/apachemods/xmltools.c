#include "xmltools.h"

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
