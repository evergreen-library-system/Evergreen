#include "xml_utils.h"


void recurse_doc( xmlNodePtr node ) {
	if( node == NULL ) return;
	printf("Recurse: %s =>  %s", node->name, node->content );
	xmlNodePtr t = node->children;
	while(t) {
		recurse_doc(t);
		t = t->next;
	}
}



jsonObject* xmlDocToJSON(xmlDocPtr doc) {
	if(!doc) return NULL;
	return _xmlToJSON(xmlDocGetRootElement(doc), NULL);
}

jsonObject* _xmlToJSON(xmlNodePtr node, jsonObject* obj) {

	if(!node) return NULL;
	if(xmlIsBlankNode(node)) return NULL;
	if(obj == NULL) obj = jsonNewObject(NULL);

	if(node->type == XML_TEXT_NODE) {
		jsonObjectSetString(obj, (char*) node->content);	

	} else if(node->type == XML_ELEMENT_NODE || node->type == XML_ATTRIBUTE_NODE ) {

		jsonObject* new_obj = jsonNewObject(NULL);

		jsonObject* old;

		/* do the duplicate node / array shuffle */
		if( (old = jsonObjectGetKey(obj, (char*) node->name)) ) {
			if(old->type == JSON_ARRAY ) {
				jsonObjectPush(old, new_obj);
			} else {
				jsonObject* arr = jsonNewObject(NULL);
				jsonObjectPush(arr, jsonObjectClone(old));
				jsonObjectPush(arr, new_obj);
				jsonObjectSetKey(obj, (char*) node->name, arr);
			}
		} else {
			jsonObjectSetKey(obj, (char*) node->name, new_obj);
		}

		xmlNodePtr child = node->children;
		while(child) {
			_xmlToJSON(child, new_obj);
			child = child->next;
		}	
	}	

	return obj;
}


char* xmlDocToString(xmlDocPtr doc, int full) {

	if(!doc) return NULL;

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


