#include "json_xml.h"
#include "fieldmapper_lookup.h"

void _rest_xml_output(growing_buffer*, jsonObject*, char*, int, int);
char* _escape_xml (char*);

char* json_string_to_xml(char* content) {
	jsonObject * obj;
	growing_buffer * res_xml;
	char * output;
	int i;

	obj = json_parse_string( content );
	res_xml = buffer_init(1024);

	if (!obj)
		return NULL;
	
	buffer_add(res_xml, "<response>");

	if(obj->type == JSON_ARRAY ) {
		for( i = 0; i!= obj->size; i++ ) {
			_rest_xml_output(res_xml, jsonObjectGetIndex(obj,i), NULL, 0,0);
		}
	} else {
		_rest_xml_output(res_xml, obj, NULL, 0,0);
	}

	buffer_add(res_xml, "</response>");

	output = buffer_data(res_xml);
	buffer_free(res_xml);
	jsonObjectFree(obj);

	return output;
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

void _rest_xml_output(growing_buffer* buf, jsonObject* obj, char * obj_class, int arr_index, int notag) {
	char * tag;
	int i;
	
	if(!obj) return;

	if (obj->classname)
		notag = 1;

	if(isFieldmapper(obj_class)) {
		tag = fm_pton(obj_class,arr_index);
	} else if(obj_class) {
		tag = strdup(obj_class);
	} else {
		tag = strdup("datum");
	}

        
   /* add class hints if we have a class name */
   if(obj->classname) {
     	if(obj->type == JSON_NULL) {
			buffer_fadd(buf,"<%s><Object class_hint=\"%s\"/></%s>", tag, obj->classname, tag);
			return;
		} else {
			buffer_fadd(buf,"<%s><Object class_hint=\"%s\">", tag, obj->classname);
		}
	}


	/* now add the data */
	if(obj->type == JSON_NULL) {
		if (!notag)
			buffer_fadd(buf, "<%s/>",tag);
	} else if(obj->type == JSON_BOOL && obj->value.b) {
		if (notag)
			buffer_add(buf, "true");
		else
			buffer_fadd(buf, "<%s>true</%s>",tag,tag);
                
	} else if(obj->type == JSON_BOOL && ! obj->value.b) {
		if (notag)
			buffer_add(buf, "false");
		else
			buffer_fadd(buf, "<%s>false</%s>",tag,tag);

	} else if (obj->type == JSON_STRING) {
		if (notag) {
			char * t = _escape_xml(jsonObjectGetString(obj));
			buffer_add(buf,t);
			free(t);
		} else {
			char * t = _escape_xml(jsonObjectGetString(obj));
			buffer_fadd(buf,"<%s>%s</%s>",tag,t,tag);
			free(t);
		}

	} else if(obj->type == JSON_NUMBER) {
		double x = jsonObjectGetNumber(obj);
		if (notag) {
			if (x == (int)x)
				buffer_fadd(buf,"%d",(int)x);
			else
				buffer_fadd(buf,"%lf",x);
		} else {
			if (x == (int)x)
				buffer_fadd(buf,"<%s>%d</%s>",tag, (int)x,tag);
			else
				buffer_fadd(buf,"<%s>%lf</%s>",tag, x,tag);
		}

	} else if (obj->type == JSON_ARRAY) {
		if (!notag) {
			if(!isFieldmapper(obj_class))
        	       		buffer_add(buf,"<array>");
			else
               			buffer_fadd(buf,"<%s>",tag);
		}

	       	for( i = 0; i!= obj->size; i++ ) {
			_rest_xml_output(buf, jsonObjectGetIndex(obj,i), obj->classname, i,0);
		}

		if (!notag) {
			if(!isFieldmapper(obj_class))
        	       		buffer_add(buf,"</array>");
			else
               			buffer_fadd(buf,"</%s>",tag);
		}

        } else if (obj->type == JSON_HASH) {

		if (!notag) {
			if(!obj_class)
        	       		buffer_add(buf,"<hash>");
			else
               			buffer_fadd(buf,"<%s>",tag);
		}

                jsonObjectIterator* itr = jsonNewObjectIterator(obj);
                jsonObjectNode* tmp;
                while( (tmp = jsonObjectIteratorNext(itr)) ) {
			if (notag) {
				buffer_fadd(buf,"<%s>",tmp->key);
			} else {
				buffer_add(buf,"<pair>");
				buffer_fadd(buf,"<key>%s</key><value>",tmp->key);
			}

                        _rest_xml_output(buf, tmp->item, NULL,0,notag);

			if (notag) {
				buffer_fadd(buf,"</%s>",tmp->key);
			} else {
				buffer_add(buf,"</value></pair>");
			}
                }
                jsonObjectIteratorFree(itr);

		if (!notag) {
			if(!obj_class)
        	       		buffer_add(buf,"</hash>");
			else
               			buffer_fadd(buf,"</%s>",tag);
		}

	}

	if (obj->classname)
                buffer_fadd(buf,"</Object></%s>",tag);

	free(tag);
}

