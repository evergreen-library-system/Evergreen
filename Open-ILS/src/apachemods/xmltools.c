#include "xmltools.h"


#ifdef XMLTOOLS_DEBUG // standalone debugging 

int main(int argc, char* argv[]) {

	char* file = argv[1];
	char* dtdfile = argv[2];

	xmlDocPtr doc;


	/*
	xmlSubstituteEntitiesDefault(0);
	xmlParserCtxtPtr ctxt = xmlNewParserCtxt();
	doc = xmlCtxtReadFile(ctxt, file, NULL, XML_PARSE_NOENT | XML_PARSE_RECOVER | XML_PARSE_XINCLUDE | XML_PARSE_NOERROR | XML_PARSE_NOWARNING );
	if(doc != NULL) 
		fprintf(stderr, "What we have so far:\n%s\n", xmlDocToString(doc, 1));
	else {
		fprintf(stderr, "NO Doc\n");
		return 0;
	}

	exit(99);
	*/

	/* parse the doc */
	if( (doc = xmlParseFile(file)) == NULL) {
		fprintf(stderr, "\n ^-- Error parsing XML file %s\n", file);
		fflush(stderr);
		return 99;
	}

	/* process xincludes */
	if( xmlXIncludeProcessFlags(doc, XML_PARSE_NOENT) < 0 ) {
		fprintf(stderr, "\n ^-- Error processing XIncludes for file %s\n", file);
		if(doc != NULL) 
			fprintf(stderr, "What we have so far:\n%s\n", xmlDocToString(doc, 1));
		fflush(stderr);
		return 99;
	}


	/* replace the DTD */
	if(xmlReplaceDtd(doc, dtdfile) < 0) {
		fprintf(stderr, "Error replacing DTD file with file %s\n", dtdfile);
		fflush(stderr);
		return 99;
	}

	/* force DTD entity replacement */
	doc = xmlProcessDtdEntities(doc);

	/* stringify */
	char* xml = xmlDocToString(doc, 0);

	fprintf(stderr, "%s\n", xml);

	/* deallocate */
	free(dtdfile);
	free(xml);
	xmlFreeDoc(doc);
	xmlCleanupCharEncodingHandlers();
	xmlCleanupParser();


}

#endif

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
