#include "osrf_message.h"

osrf_message* osrf_message_init( enum M_TYPE type, int thread_trace, int protocol ) {

	osrf_message* msg			= (osrf_message*) safe_malloc(sizeof(osrf_message));
	msg->m_type					= type;
	msg->thread_trace			= thread_trace;
	msg->protocol				= protocol;
	msg->next					= NULL;
	msg->is_exception			= 0;
	msg->_params				= NULL;
	msg->_result_content		= NULL;

	return msg;
}


void osrf_message_set_method( osrf_message* msg, char* method_name ) {
	if( msg == NULL || method_name == NULL ) return;
	msg->method_name = strdup( method_name );
}


void osrf_message_add_object_param( osrf_message* msg, object* o ) {
	if(!msg|| !o) return;
	if(!msg->_params)
		msg->_params = json_parse_string("[]");
	char* j = o->to_json(o);
	msg->_params->push(msg->_params, json_parse_string(j));
	free(j);
}

void osrf_message_set_params( osrf_message* msg, object* o ) {
	if(!msg || !o) return;

	if(!o->is_array) {
		warning_handler("passing non-array to osrf_message_set_params()");
		return;
	}

	if(msg->_params) free_object(msg->_params);

	char* j = o->to_json(o);
	msg->_params = json_parse_string(j);
	free(j);
}


/* only works if parse_json_params is false */
void osrf_message_add_param( osrf_message* msg, char* param_string ) {
	if(msg == NULL || param_string == NULL) return;
	if(!msg->_params) msg->_params = new_object(NULL);
	msg->_params->push(msg->_params, json_parse_string(param_string));
}


void osrf_message_set_status_info( 
		osrf_message* msg, char* status_name, char* status_text, int status_code ) {

	if( msg == NULL )
		fatal_handler( "Bad params to osrf_message_set_status_info()" );

	if( status_name != NULL ) 
		msg->status_name = strdup( status_name );

	if( status_text != NULL )
		msg->status_text = strdup( status_text );

	msg->status_code = status_code;
}


void osrf_message_set_result_content( osrf_message* msg, char* json_string ) {
	if( msg == NULL || json_string == NULL)
		warning_handler( "Bad params to osrf_message_set_result_content()" );

	msg->result_string =	strdup(json_string);
	if(json_string) msg->_result_content = json_parse_string(json_string);
}



void osrf_message_free( osrf_message* msg ) {
	if( msg == NULL )
		return;

	if( msg->status_name != NULL )
		free(msg->status_name);

	if( msg->status_text != NULL )
		free(msg->status_text);

	if( msg->_result_content != NULL )
		free_object( msg->_result_content );

	if( msg->result_string != NULL )
		free( msg->result_string);

	if( msg->method_name != NULL )
		free(msg->method_name);

	if( msg->_params != NULL )
		free_object(msg->_params);

	free(msg);
}

char* osrf_message_serialize(osrf_message* msg) {
	if( msg == NULL ) return NULL;
	object* json = new_object(NULL);
	json->set_class(json, "osrfMessage");
	object* payload;
	char sc[64]; memset(sc,0,64);

	char* str;

	char tt[64];
	memset(tt,0,64);
	sprintf(tt,"%d",msg->thread_trace);
	json->add_key(json, "threadTrace", new_object(tt));

	switch(msg->m_type) {
		
		case CONNECT: 
			json->add_key(json, "type", new_object("CONNECT"));
			break;

		case DISCONNECT: 
			json->add_key(json, "type", new_object("DISCONNECT"));
			break;

		case STATUS:
			json->add_key(json, "type", new_object("STATUS"));
			payload = new_object(NULL);
			payload->set_class(payload, msg->status_name);
			payload->add_key(payload, "status", new_object(msg->status_text));
         sprintf(sc,"%d",msg->status_code);
			payload->add_key(payload, "statusCode", new_object(sc));
			json->add_key(json, "payload", payload);
			break;

		case REQUEST:
			json->add_key(json, "type", new_object("REQUEST"));
			payload = new_object(NULL);
			payload->set_class(payload, "osrfMethod");
			payload->add_key(payload, "method", new_object(msg->method_name));
			str = object_to_json(msg->_params);
			payload->add_key(payload, "params", json_parse_string(str));
			free(str);
			json->add_key(json, "payload", payload);

			break;

		case RESULT:
			json->add_key(json, "type", new_object("RESULT"));
			payload = new_object(NULL);
			payload->set_class(payload,"osrfResult");
			payload->add_key(payload, "status", new_object(msg->status_text));
         sprintf(sc,"%d",msg->status_code);
			payload->add_key(payload, "statusCode", new_object(sc));
			str = object_to_json(msg->_result_content);
			payload->add_key(payload, "content", json_parse_string(str));
			free(str);
			json->add_key(json, "payload", payload);
			break;
	}
	
	object* wrapper = new_object(NULL);
	wrapper->push(wrapper, json);
	char* j = wrapper->to_json(wrapper);
	free_object(wrapper);
	return j;
}


int osrf_message_deserialize(char* string, osrf_message* msgs[], int count) {
	if(!string || !msgs || count <= 0) return 0;
	int numparsed = 0;
	object* json = json_parse_string(string);
	if(json == NULL) return 0;
	int x;


	for( x = 0; x < json->size && x < count; x++ ) {

		object* message = json->get_index(json, x);

		if(message && !message->is_null && 
			message->classname && !strcmp(message->classname, "osrfMessage")) {

			osrf_message* new_msg = safe_malloc(sizeof(osrf_message));

			object* tmp = message->get_key(message, "type");

			if(tmp && tmp->string_data) {
				char* t = tmp->string_data;

				if(!strcmp(t, "CONNECT")) 		new_msg->m_type = CONNECT;
				if(!strcmp(t, "DISCONNECT")) 	new_msg->m_type = DISCONNECT;
				if(!strcmp(t, "STATUS")) 		new_msg->m_type = STATUS;
				if(!strcmp(t, "REQUEST")) 		new_msg->m_type = REQUEST;
				if(!strcmp(t, "RESULT")) 		new_msg->m_type = RESULT;
			}

			tmp = message->get_key(message, "threadTrace");
			if(tmp) {
				if(tmp->is_number)
					new_msg->thread_trace = tmp->num_value;
				if(tmp->is_string)
					new_msg->thread_trace = atoi(tmp->string_data);
			}


			tmp = message->get_key(message, "protocol");
			if(tmp) {
				if(tmp->is_number)
					new_msg->protocol = tmp->num_value;
				if(tmp->is_string)
					new_msg->protocol = atoi(tmp->string_data);
			}

			tmp = message->get_key(message, "payload");
			if(tmp) {
				if(tmp->classname)
					new_msg->status_name = strdup(tmp->classname);

				object* tmp0 = tmp->get_key(tmp,"method");
				if(tmp0 && tmp0->string_data)
					new_msg->method_name = strdup(tmp0->string_data);

				tmp0 = tmp->get_key(tmp,"params");
				if(tmp0) {
					char* s = tmp0->to_json(tmp0);
					new_msg->_params = json_parse_string(s);
					free(s);
				}

				tmp0 = tmp->get_key(tmp,"status");
				if(tmp0 && tmp0->string_data)
					new_msg->status_text = strdup(tmp0->string_data);

				tmp0 = tmp->get_key(tmp,"statusCode");
				if(tmp0) {
					if(tmp0->is_string && tmp0->string_data)
						new_msg->status_code = atoi(tmp0->string_data);
					if(tmp0->is_number)
						new_msg->status_code = tmp0->num_value;
				}

				tmp0 = tmp->get_key(tmp,"content");
				if(tmp0) {
					char* s = tmp0->to_json(tmp0);
					new_msg->_result_content = json_parse_string(s);
					free(s);
				}

			}
			msgs[numparsed++] = new_msg;
		}
	}
	free_object(json);
	return numparsed;
}


