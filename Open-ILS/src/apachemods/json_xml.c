#include "json_xml.h"
#include "fieldmapper_lookup.h"

void _rest_xml_output(growing_buffer*, object*, char*, int, int);
char* _escape_xml (char*);

char* json_string_to_xml(char* content) {
	object * obj;
	growing_buffer * res_xml;
	char * output;
	int i;

	obj = json_parse_string( content );
	res_xml = buffer_init(1024);

	if (!obj)
		return NULL;
	
	buffer_add(res_xml, "<response>");

	if(obj->is_array) {
		for( i = 0; i!= obj->size; i++ ) {
			_rest_xml_output(res_xml, obj->get_index(obj,i), NULL, 0,0);
		}
	} else {
		_rest_xml_output(res_xml, obj, NULL, 0,0);
	}

	buffer_add(res_xml, "</response>");

	output = buffer_data(res_xml);
	buffer_free(res_xml);
	free_object(obj);

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

void _rest_xml_output(growing_buffer* buf, object* obj, char * obj_class, int arr_index, int notag) {
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
     	if(obj->is_null) {
			buffer_fadd(buf,"<%s><Object class_hint=\\\"%s\\\"/></%s>", tag, obj->classname, tag);
			return;
		} else {
			buffer_fadd(buf,"<%s><Object class_hint=\\\"%s\\\">", tag, obj->classname);
		}
	}


	/* now add the data */
	if(obj->is_null) {
		if (!notag)
			buffer_fadd(buf, "<%s/>",tag);
	} else if(obj->is_bool && obj->bool_value) {
		if (notag)
			buffer_add(buf, "true");
		else
			buffer_fadd(buf, "<%s>true</%s>",tag,tag);
                
	} else if(obj->is_bool && ! obj->bool_value) {
		if (notag)
			buffer_add(buf, "false");
		else
			buffer_fadd(buf, "<%s>false</%s>",tag,tag);

	} else if (obj->is_string) {
		if (notag) {
			char * t = _escape_xml(obj->string_data);
			buffer_add(buf,t);
			free(t);
		} else {
			char * t = _escape_xml(obj->string_data);
			buffer_fadd(buf,"<%s>%s</%s>",tag,t,tag);
			free(t);
		}

	} else if(obj->is_number) {

		if (notag)
			buffer_fadd(buf,"%ld",obj->num_value);
		else
			buffer_fadd(buf,"<%s>%ld</%s>",tag,obj->num_value,tag);


	} else if(obj->is_double) {
		if (notag)
			buffer_fadd(buf,"%lf",tag,obj->double_value,tag);
		else
			buffer_fadd(buf,"<%s>%lf</%s>",tag,obj->double_value,tag);


	} else if (obj->is_array) {
		if (!notag) {
			if(!isFieldmapper(obj_class))
        	       		buffer_add(buf,"<array>");
			else
               			buffer_fadd(buf,"<%s>",tag);
		}

	       	for( i = 0; i!= obj->size; i++ ) {
			_rest_xml_output(buf, obj->get_index(obj,i), obj->classname, i,0);
		}

		if (!notag) {
			if(!isFieldmapper(obj_class))
        	       		buffer_add(buf,"</array>");
			else
               			buffer_fadd(buf,"</%s>",tag);
		}

        } else if (obj->is_hash) {

		if (!notag) {
			if(!obj_class)
        	       		buffer_add(buf,"<hash>");
			else
               			buffer_fadd(buf,"<%s>",tag);
		}

                object_iterator* itr = new_iterator(obj);
                object_node* tmp;
                while( (tmp = itr->next(itr)) ) {
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
                free_iterator(itr);

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

