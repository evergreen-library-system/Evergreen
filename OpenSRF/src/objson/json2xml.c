
#include "json2xml.h"

static char* _escape_xml (char*);
static int _recurse_jsonObjectToXML(jsonObject*, growing_buffer*);

char* jsonObjectToXML(jsonObject* obj) {

	growing_buffer * res_xml;
	char * output;

	res_xml = buffer_init(1024);

	if (!obj)
		return strdup("<null/>");
	
	_recurse_jsonObjectToXML( obj, res_xml );
	output = buffer_data(res_xml);
	
	buffer_free(res_xml);

	return output;

}

int _recurse_jsonObjectToXML(jsonObject* obj, growing_buffer* res_xml) {

	char * hint = NULL;
	char * bool_val = NULL;
	int i = 0;
	
	if (obj->classname)
		hint = strdup(obj->classname);

	if(obj->type == JSON_NULL) {

		if (hint)
			buffer_fadd(res_xml, "<null class_hint=\"%s\"/>",hint);
		else
			buffer_add(res_xml, "<null/>");

	} else if(obj->type == JSON_BOOL) {

		if (obj->value.b)
			bool_val = strdup("true");
		else
			bool_val = strdup("false");

		if (hint)
			buffer_fadd(res_xml, "<boolean value=\"%s\" class_hint=\"%s\"/>", bool_val, hint);
		else
			buffer_fadd(res_xml, "<boolean value=\"%s\"/>", bool_val);

		free(bool_val);
                
	} else if (obj->type == JSON_STRING) {
		if (hint) {
			char * t = _escape_xml(jsonObjectGetString(obj));
			buffer_fadd(res_xml,"<string class_hint=\"%s\">%s</string>", hint, t);
			free(t);
		} else {
			char * t = _escape_xml(jsonObjectGetString(obj));
			buffer_fadd(res_xml,"<string>%s</string>", t);
			free(t);
		}

	} else if(obj->type == JSON_NUMBER) {
		double x = jsonObjectGetNumber(obj);
		if (hint) {
			if (x == (int)x)
				buffer_fadd(res_xml,"<number class_hint=\"%s\">%d</number>", hint, (int)x);
			else
				buffer_fadd(res_xml,"<number class_hint=\"%s\">%lf</number>", hint, x);
		} else {
			if (x == (int)x)
				buffer_fadd(res_xml,"<number>%d</number>", (int)x);
			else
				buffer_fadd(res_xml,"<number>%lf</number>", x);
		}

	} else if (obj->type == JSON_ARRAY) {

		if (hint) 
        	       	buffer_fadd(res_xml,"<array class_hint=\"%s\">", hint);
		else
               		buffer_add(res_xml,"<array>");

	       	for ( i = 0; i!= obj->size; i++ )
			_recurse_jsonObjectToXML(jsonObjectGetIndex(obj,i), res_xml);

		buffer_add(res_xml,"</array>");

	} else if (obj->type == JSON_HASH) {

		if (hint)
        	       	buffer_fadd(res_xml,"<object class_hint=\"%s\">", hint);
		else
			buffer_add(res_xml,"<object>");

                jsonObjectIterator* itr = jsonNewObjectIterator(obj);
                jsonObjectNode* tmp;
                while( (tmp = jsonObjectIteratorNext(itr)) ) {

			buffer_fadd(res_xml,"<element key=\"%s\">",tmp->key);

			_recurse_jsonObjectToXML(tmp->item, res_xml);

			buffer_add(res_xml,"</element>");
                }
                jsonObjectIteratorFree(itr);

		buffer_add(res_xml,"</object>");
	}

	if (hint)
		free(hint);

	return 1;
}

char* _escape_xml (char* text) {
	char* out;
	growing_buffer* b = buffer_init(256);
	int len = strlen(text);
	int i;
	for (i = 0; i < len; i++) {
		if (text[i] == '&')
			buffer_add(b,"&amp;");
		else if (text[i] == '<')
			buffer_add(b,"&lt;");
		else if (text[i] == '>')
			buffer_add(b,"&gt;");
		else
			buffer_add_char(b,text[i]);
	}
	out = buffer_data(b);
	buffer_free(b);
	return out;
}


