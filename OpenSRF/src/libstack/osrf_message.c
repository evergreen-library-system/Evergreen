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


void osrf_message_add_object_param( osrf_message* msg, jsonObject* o ) {
	if(!msg|| !o) return;
	if(!msg->_params)
		msg->_params = jsonParseString("[]");
	char* j = jsonObjectToJSON(o);
	jsonObjectPush(msg->_params, jsonParseString(j));
	free(j);
}

void osrf_message_set_params( osrf_message* msg, jsonObject* o ) {
	if(!msg || !o) return;

	if(!o->type == JSON_ARRAY) {
		warning_handler("passing non-array to osrf_message_set_params()");
		return;
	}

	if(msg->_params) jsonObjectFree(msg->_params);

	char* j = jsonObjectToJSON(o);
	msg->_params = jsonParseString(j);
	free(j);
}


/* only works if parse_json_params is false */
void osrf_message_add_param( osrf_message* msg, char* param_string ) {
	if(msg == NULL || param_string == NULL) return;
	if(!msg->_params) msg->_params = jsonNewObject(NULL);
	jsonObjectPush(msg->_params, jsonParseString(param_string));
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
	if(json_string) msg->_result_content = jsonParseString(json_string);
}



void osrfMessageFree( osrfMessage* msg ) {
	osrf_message_free( msg );
}

void osrf_message_free( osrf_message* msg ) {
	if( msg == NULL )
		return;

	if( msg->status_name != NULL )
		free(msg->status_name);

	if( msg->status_text != NULL )
		free(msg->status_text);

	if( msg->_result_content != NULL )
		jsonObjectFree( msg->_result_content );

	if( msg->result_string != NULL )
		free( msg->result_string);

	if( msg->method_name != NULL )
		free(msg->method_name);

	if( msg->_params != NULL )
		jsonObjectFree(msg->_params);

	free(msg);
}


char* osrfMessageSerializeBatch( osrfMessage* msgs [], int count ) {
	if( !msgs ) return NULL;

	char* j;
	int i = 0;
	osrfMessage* msg = NULL;
	jsonObject* wrapper = jsonNewObject(NULL);

	while( ((msg = msgs[i]) && (i++ < count)) ) 
		jsonObjectPush(wrapper, osrfMessageToJSON( msg ));

	j = jsonObjectToJSON(wrapper);
	jsonObjectFree(wrapper);

	return j;	
}


char* osrf_message_serialize(osrf_message* msg) {

	if( msg == NULL ) return NULL;
	char* j = NULL;

	jsonObject* json = osrfMessageToJSON( msg );

	if(json) {
		jsonObject* wrapper = jsonNewObject(NULL);
		jsonObjectPush(wrapper, json);
		j = jsonObjectToJSON(wrapper);
		jsonObjectFree(wrapper);
	}

	return j;
}


jsonObject* osrfMessageToJSON( osrfMessage* msg ) {

	jsonObject* json = jsonNewObject(NULL);
	jsonObjectSetClass(json, "osrfMessage");
	jsonObject* payload;
	char sc[64]; memset(sc,0,64);

	char* str;

	INT_TO_STRING(msg->thread_trace);
	jsonObjectSetKey(json, "threadTrace", jsonNewObject(INTSTR));

	switch(msg->m_type) {
		
		case CONNECT: 
			jsonObjectSetKey(json, "type", jsonNewObject("CONNECT"));
			break;

		case DISCONNECT: 
			jsonObjectSetKey(json, "type", jsonNewObject("DISCONNECT"));
			break;

		case STATUS:
			jsonObjectSetKey(json, "type", jsonNewObject("STATUS"));
			payload = jsonNewObject(NULL);
			jsonObjectSetClass(payload, msg->status_name);
			jsonObjectSetKey(payload, "status", jsonNewObject(msg->status_text));
         sprintf(sc,"%d",msg->status_code);
			jsonObjectSetKey(payload, "statusCode", jsonNewObject(sc));
			jsonObjectSetKey(json, "payload", payload);
			break;

		case REQUEST:
			jsonObjectSetKey(json, "type", jsonNewObject("REQUEST"));
			payload = jsonNewObject(NULL);
			jsonObjectSetClass(payload, "osrfMethod");
			jsonObjectSetKey(payload, "method", jsonNewObject(msg->method_name));
			str = jsonObjectToJSON(msg->_params);
			jsonObjectSetKey(payload, "params", jsonParseString(str));
			free(str);
			jsonObjectSetKey(json, "payload", payload);

			break;

		case RESULT:
			jsonObjectSetKey(json, "type", jsonNewObject("RESULT"));
			payload = jsonNewObject(NULL);
			jsonObjectSetClass(payload,"osrfResult");
			jsonObjectSetKey(payload, "status", jsonNewObject(msg->status_text));
         sprintf(sc,"%d",msg->status_code);
			jsonObjectSetKey(payload, "statusCode", jsonNewObject(sc));
			str = jsonObjectToJSON(msg->_result_content);
			jsonObjectSetKey(payload, "content", jsonParseString(str));
			free(str);
			jsonObjectSetKey(json, "payload", payload);
			break;
	}

	return json;
}


int osrf_message_deserialize(char* string, osrf_message* msgs[], int count) {

	if(!string || !msgs || count <= 0) return 0;
	int numparsed = 0;

	jsonObject* json = jsonParseString(string);

	if(!json) {
		warning_handler(
			"osrf_message_deserialize() unable to parse data: \n%s\n", string);
		return 0;
	}

	int x;

	for( x = 0; x < json->size && x < count; x++ ) {

		jsonObject* message = jsonObjectGetIndex(json, x);

		if(message && message->type != JSON_NULL && 
			message->classname && !strcmp(message->classname, "osrfMessage")) {

			osrf_message* new_msg = safe_malloc(sizeof(osrf_message));

			jsonObject* tmp = jsonObjectGetKey(message, "type");

			char* t;
			if( ( t = jsonObjectGetString(tmp)) ) {

				if(!strcmp(t, "CONNECT")) 		new_msg->m_type = CONNECT;
				if(!strcmp(t, "DISCONNECT")) 	new_msg->m_type = DISCONNECT;
				if(!strcmp(t, "STATUS")) 		new_msg->m_type = STATUS;
				if(!strcmp(t, "REQUEST")) 		new_msg->m_type = REQUEST;
				if(!strcmp(t, "RESULT")) 		new_msg->m_type = RESULT;
			}

			tmp = jsonObjectGetKey(message, "threadTrace");
			if(tmp) {
				char* tt = jsonObjectToSimpleString(tmp);
				if(tt) {
					new_msg->thread_trace = atoi(tt);
					free(tt);
				}
				/*
				if(tmp->type == JSON_NUMBER)
					new_msg->thread_trace = (int) jsonObjectGetNumber(tmp);
				if(tmp->type == JSON_STRING)
					new_msg->thread_trace = atoi(jsonObjectGetString(tmp));
					*/
			}


			tmp = jsonObjectGetKey(message, "protocol");

			if(tmp) {
				char* proto = jsonObjectToSimpleString(tmp);
				if(proto) {
					new_msg->protocol = atoi(proto);
					free(proto);
				}

				/*
				if(tmp->type == JSON_NUMBER)
					new_msg->protocol = (int) jsonObjectGetNumber(tmp);
				if(tmp->type == JSON_STRING)
					new_msg->protocol = atoi(jsonObjectGetString(tmp));
					*/
			}

			tmp = jsonObjectGetKey(message, "payload");
			if(tmp) {
				if(tmp->classname)
					new_msg->status_name = strdup(tmp->classname);

				jsonObject* tmp0 = jsonObjectGetKey(tmp,"method");
				if(jsonObjectGetString(tmp0))
					new_msg->method_name = strdup(jsonObjectGetString(tmp0));

				tmp0 = jsonObjectGetKey(tmp,"params");
				if(tmp0) {
					char* s = jsonObjectToJSON(tmp0);
					new_msg->_params = jsonParseString(s);
					free(s);
				}

				tmp0 = jsonObjectGetKey(tmp,"status");
				if(jsonObjectGetString(tmp0))
					new_msg->status_text = strdup(jsonObjectGetString(tmp0));

				tmp0 = jsonObjectGetKey(tmp,"statusCode");
				if(tmp0) {
					if(jsonObjectGetString(tmp0))
						new_msg->status_code = atoi(jsonObjectGetString(tmp0));
					if(tmp0->type == JSON_NUMBER)
						new_msg->status_code = (int) jsonObjectGetNumber(tmp0);
				}

				tmp0 = jsonObjectGetKey(tmp,"content");
				if(tmp0) {
					char* s = jsonObjectToJSON(tmp0);
					new_msg->_result_content = jsonParseString(s);
					free(s);
				}

			}
			msgs[numparsed++] = new_msg;
		}
	}

	jsonObjectFree(json);
	return numparsed;
}



jsonObject* osrfMessageGetResult( osrfMessage* msg ) {
	if(msg) return msg->_result_content;
	return NULL;
}

