#include "opensrf/osrf_message.h"



/*
int main() {

	char* x = "<oils:root xmlns:oils='http://open-ils.org/xml/namespaces/oils_v1'><oils:domainObject name='oilsMessage'><oils:domainObjectAttr value='STATUS' name='type'/><oils:domainObjectAttr value='12' name='threadTrace'/><oils:domainObject name='oilsMethodException'><oils:domainObjectAttr value=' *** Call to [div] failed for session [1351200643.110915057523738], thread trace [12]:&#10;JabberDisconnected Exception &#10;This JabberClient instance is no longer connected to the server' name='status'/><oils:domainObjectAttr value='500' name='statusCode'/></oils:domainObject></oils:domainObject></oils:root>";
	*/

	/*
	char* x = "<oils:root xmlns:oils='http://open-ils.org/xml/namespaces/oils_v1'>"
				"<oils:domainObject name='oilsMessage'>"
				"<oils:domainObjectAttr value='STATUS' name='type'/>"
				"<oils:domainObjectAttr value='1' name='threadTrace'/>"
				"<oils:domainObject name='oilsConnectStatus'>"
				"<oils:domainObjectAttr value='Connection Successful' name='status'/>"
				"<oils:domainObjectAttr value='200' name='statusCode'/>"
				"</oils:domainObject></oils:domainObject>"

				"<oils:domainObject name='oilsMessage'>"
				"<oils:domainObjectAttr value='STATUS' name='type'/>"
				"<oils:domainObjectAttr value='1' name='threadTrace'/>"
				"<oils:domainObject name='oilsConnectStatus'>"
				"<oils:domainObjectAttr value='Request Complete' name='status'/>"
				"<oils:domainObjectAttr value='205' name='statusCode'/>"
				"</oils:domainObject></oils:domainObject>"
				
				"</oils:root>";
				*/

/*
	osrf_message* arr[4];
	memset(arr, 0, 4);
	int ret = osrf_message_from_xml( x, arr );
	fprintf(stderr, "RET: %d\n", ret );
	if(ret<=0)
		fatal_handler( "none parsed" );

	osrf_message* xml_msg = arr[0];
	printf("Message name: %s\nstatus %s, \nstatusCode %d\n", xml_msg->status_name, xml_msg->status_text, xml_msg->status_code );

//	xml_msg = arr[1];
//	printf("Message 2 status %s, statusCode %d\n", xml_msg->status_text, xml_msg->status_code );


	return 0;
}
*/



	/*
	osrf_message* msg = osrf_message_init( STATUS, 1, 1 );
//	osrf_message* msg = osrf_message_init( CONNECT, 1, 1 );
	//osrf_message* msg = osrf_message_init( REQUEST, 1, 1 );
	osrf_message_set_status_info( msg, "oilsConnectStatus", "Connection Succsesful", 200 );

	json* params = json_object_new_array();
	json_object_array_add(params, json_object_new_int(1));
	json_object_array_add(params, json_object_new_int(2));

	osrf_message_set_request_info( msg, "add", params );
	//osrf_message_set_result_content( msg, params );
	json_object_put( params );

	char* xml =  osrf_message_to_xml( msg );
	printf( "\n\nMessage as XML\n%s", xml );

	osrf_message* xml_msg = osrf_message_from_xml( xml );

	printf( "Message stuff \n\ntype %d"
			"\nthread_trace %d \nprotocol %d "
			"\nstatus_name %s"
			"\nstatus_text %s\nstatus_code %d" 
			"\nresult_content %s \nparams %s"
			"\n", xml_msg->m_type, 
			xml_msg->thread_trace, xml_msg->protocol, xml_msg->status_name, 
			xml_msg->status_text, xml_msg->status_code, 
			json_object_to_json_string( xml_msg->result_content),
			json_object_to_json_string(xml_msg->params) 
			);


	free(xml);
	osrf_message_free( msg );
	osrf_message_free( xml_msg );
	return 0;
	
}
*/


osrf_message* osrf_message_init( enum M_TYPE type, int thread_trace, int protocol ) {

	osrf_message* msg = safe_malloc(sizeof(osrf_message));
	msg->m_type = type;
	msg->thread_trace = thread_trace;
	msg->protocol = protocol;
	msg->next = NULL;

	return msg;
}


void osrf_message_set_request_info( osrf_message* msg, char* method_name, json* json_params ) {
	if( msg == NULL || method_name == NULL )
		fatal_handler( "Bad params to osrf_message_set_request_params()" );

	if( json_params != NULL )
		msg->params = json_tokener_parse(json_object_to_json_string(json_params));
	else
		msg->params = json_tokener_parse("[]");

	msg->method_name = strdup( method_name );
}



void osrf_message_set_status_info( 
		osrf_message* msg, char* status_name, char* status_text, int status_code ) {

	if( msg == NULL )
		fatal_handler( "Bad params to osrf_message_set_status_info()" );

	if( msg->m_type == STATUS ) 
		if( status_name != NULL ) 
			msg->status_name = strdup( status_name );

	if( status_text != NULL )
		msg->status_text = strdup( status_text );

	msg->status_code = status_code;
}


void osrf_message_set_result_content( osrf_message* msg, json* result_content ) {
	if( msg == NULL )
		fatal_handler( "Bad params to osrf_message_set_result_content()" );
	msg->result_content = json_tokener_parse(json_object_to_json_string(result_content));
}



void osrf_message_free( osrf_message* msg ) {
	if( msg == NULL )
		warning_handler( "Trying to delete NULL osrf_message" );

	if( msg->status_name != NULL )
		free(msg->status_name);

	if( msg->status_text != NULL )
		free(msg->status_text);

	if( msg->result_content != NULL )
		json_object_put( msg->result_content );

	if( msg->method_name != NULL )
		free(msg->method_name);

	if( msg->params != NULL )
		json_object_put( msg->params );

	free(msg);
}


		
/* here's where things get interesting */
char* osrf_message_to_xml( osrf_message* msg ) {

	if( msg == NULL )
		return NULL;

	int			bufsize;
	xmlChar*		xmlbuf;
	char*			encoded_msg;

	xmlKeepBlanksDefault(0);

	xmlNodePtr	message_node;
	xmlNodePtr	type_node;
	xmlNodePtr	thread_trace_node;
	xmlNodePtr	protocol_node;
	xmlNodePtr	status_node;
	xmlNodePtr	status_text_node;
	xmlNodePtr	status_code_node;
	xmlNodePtr	method_node;
	xmlNodePtr	method_name_node;
	xmlNodePtr	params_node;
	xmlNodePtr	result_node;
	xmlNodePtr	content_node;


	xmlDocPtr	doc = xmlReadDoc( 
			BAD_CAST "<oils:root xmlns:oils='http://open-ils.org/xml/namespaces/oils_v1'>"
			"<oils:domainObject name='oilsMessage'/></oils:root>", 
			NULL, NULL, XML_PARSE_NSCLEAN );

	message_node = xmlDocGetRootElement(doc)->children; /* since it's the only child */
	type_node = xmlNewChild( message_node, NULL, BAD_CAST "domainObjectAttr", NULL );
	thread_trace_node = xmlNewChild( message_node, NULL, BAD_CAST "domainObjectAttr", NULL );
	protocol_node = xmlNewChild( message_node, NULL, BAD_CAST "domainObjectAttr", NULL );

	char tt[64];
	memset(tt,0,64);
	sprintf(tt,"%d",msg->thread_trace);
	xmlSetProp( thread_trace_node, BAD_CAST "name", BAD_CAST "threadTrace" );
	xmlSetProp( thread_trace_node, BAD_CAST "value", BAD_CAST tt );

	char prot[64];
	memset(prot,0,64);
	sprintf(prot,"%d",msg->protocol);
	xmlSetProp( protocol_node, BAD_CAST "name", BAD_CAST "protocol" );
	xmlSetProp( protocol_node, BAD_CAST "value", BAD_CAST prot );

	switch(msg->m_type) {

		case CONNECT: 
			xmlSetProp( type_node, BAD_CAST "name", BAD_CAST "type" );
			xmlSetProp( type_node, BAD_CAST "value", BAD_CAST "CONNECT" );
			break;

		case DISCONNECT:
			xmlSetProp( type_node, BAD_CAST "name", BAD_CAST "type" );
			xmlSetProp( type_node, BAD_CAST "value", BAD_CAST "DISCONNECT" );
			break;

		case STATUS:

			xmlSetProp( type_node, BAD_CAST "name", BAD_CAST "type" );
			xmlSetProp( type_node, BAD_CAST "value", BAD_CAST "STATUS" );
			status_node = xmlNewChild( message_node, NULL, BAD_CAST "domainObject", NULL );
			xmlSetProp( status_node, BAD_CAST "name", BAD_CAST msg->status_name );

			status_text_node = xmlNewChild( status_node, NULL, BAD_CAST "domainObjectAttr", NULL );
			xmlSetProp( status_text_node, BAD_CAST "name", BAD_CAST "status" );
			xmlSetProp( status_text_node, BAD_CAST "value", BAD_CAST msg->status_text);

			status_code_node = xmlNewChild( status_node, NULL, BAD_CAST "domainObjectAttr", NULL );
			xmlSetProp( status_code_node, BAD_CAST "name", BAD_CAST "statusCode" );

			char sc[64];
			memset(sc,0,64);
			sprintf(sc,"%d",msg->status_code);
			xmlSetProp( status_code_node, BAD_CAST "value", BAD_CAST sc);
			
			break;

		case REQUEST:

			xmlSetProp( type_node, BAD_CAST "name", "type" );
			xmlSetProp( type_node, BAD_CAST "value", "REQUEST" );
			method_node = xmlNewChild( message_node, NULL, BAD_CAST "domainObject", NULL );
			xmlSetProp( method_node, BAD_CAST "name", BAD_CAST "oilsMethod" );

			if( msg->method_name != NULL ) {

				method_name_node = xmlNewChild( method_node, NULL, BAD_CAST "domainObjectAttr", NULL );
				xmlSetProp( method_name_node, BAD_CAST "name", BAD_CAST "method" );
				xmlSetProp( method_name_node, BAD_CAST "value", BAD_CAST msg->method_name );

				if( msg->params != NULL ) {
					params_node = xmlNewChild( method_node, NULL, 
						BAD_CAST "params", BAD_CAST json_object_to_json_string( msg->params ) );
				}
			}

			break;

		case RESULT:

			xmlSetProp( type_node, BAD_CAST "name", BAD_CAST "type" );
			xmlSetProp( type_node, BAD_CAST "value", BAD_CAST "RESULT" );
			result_node = xmlNewChild( message_node, NULL, BAD_CAST "domainObject", NULL );
			xmlSetProp( result_node, BAD_CAST "name", BAD_CAST "oilsResult" );

			status_text_node = xmlNewChild( result_node, NULL, BAD_CAST "domainObjectAttr", NULL );
			xmlSetProp( status_text_node, BAD_CAST "name", BAD_CAST "status" );
			xmlSetProp( status_text_node, BAD_CAST "value", BAD_CAST msg->status_text);

			status_code_node = xmlNewChild( result_node, NULL, BAD_CAST "domainObjectAttr", NULL );
			xmlSetProp( status_code_node, BAD_CAST "name", BAD_CAST "statusCode" );

			char stc[64];
			memset(stc,0,64);
			sprintf(stc,"%d",msg->status_code);
			xmlSetProp( status_code_node, BAD_CAST "value", BAD_CAST stc);

			content_node = xmlNewChild( result_node, NULL, 
					BAD_CAST "domainObject", BAD_CAST json_object_to_json_string( msg->result_content ) );
			xmlSetProp( content_node, BAD_CAST "name", BAD_CAST "oilsScalar" );

			break;

		default:
			warning_handler( "Recieved bogus message type" );
			return NULL;
	}


	// -----------------------------------------------------
	// Dump the XML doc to a string and remove the 
	// xml declaration
	// -----------------------------------------------------

	/* passing in a '1' means we want to retain the formatting */
	xmlDocDumpFormatMemory( doc, &xmlbuf, &bufsize, 0 );
	encoded_msg = strdup( (char*) xmlbuf );

	if( encoded_msg == NULL ) 
		fatal_handler("message_to_xml(): Out of Memory");

	xmlFree(xmlbuf);
	xmlFreeDoc( doc );
	xmlCleanupParser();


	/*** remove the XML declaration */
	int len = strlen(encoded_msg);
	char tmp[len];
	memset( tmp, 0, len );
	int i;
	int found_at = 0;

	/* when we reach the first >, take everything after it */
	for( i = 0; i!= len; i++ ) {
		if( encoded_msg[i] == 62) { /* ascii > */

			/* found_at holds the starting index of the rest of the doc*/
			found_at = i + 1; 
			break;
		}
	}

	if( found_at ) {
		/* move the shortened doc into the tmp buffer */
		strncpy( tmp, encoded_msg + found_at, len - found_at );
		/* move the tmp buffer back into the allocated space */
		memset( encoded_msg, 0, len );
		strcpy( encoded_msg, tmp );
	}

	return encoded_msg;

}


int osrf_message_from_xml( char* xml, osrf_message* msgs[] ) {

	if(!xml) return 0;

	xmlKeepBlanksDefault(0);

	xmlNodePtr	message_node;
	xmlDocPtr	doc = xmlReadDoc( 
			BAD_CAST xml, NULL, NULL, XML_PARSE_NSCLEAN );

	xmlNodePtr root =xmlDocGetRootElement(doc);
	if(!root) {
		warning_handler( "Attempt to build message from incomplete xml %s", xml );
		return 0;
	}

	int msg_index = 0;
	message_node = root->children; /* since it's the only child */

	if(!message_node) {
		warning_handler( "Attempt to build message from incomplete xml %s", xml );
		return 0;
	}

	while( message_node != NULL ) {

		xmlNodePtr cur_node = message_node->children;
		osrf_message* new_msg = safe_malloc(sizeof(osrf_message));
	

		while( cur_node ) {

			xmlChar* name = NULL; 
			xmlChar* value = NULL;
			
			/* we're a domainObjectAttr */
			if( !strcmp((char*)cur_node->name,"domainObjectAttr" )) {
				name = xmlGetProp( cur_node, BAD_CAST "name");
	
				if(name) {
	
					value = xmlGetProp( cur_node, BAD_CAST "value" );
					if(value) {
	
						if( (!strcmp((char*)name, "type")) ) { /* what type are we? */
	
							if(!strcmp((char*)value, "CONNECT"))
								new_msg->m_type = CONNECT;
	
							if(!strcmp((char*)value, "DISCONNECT"))
								new_msg->m_type = DISCONNECT;
		
							if(!strcmp((char*)value, "STATUS"))
								new_msg->m_type = STATUS;
		
							if(!strcmp((char*)value, "REQUEST"))
								new_msg->m_type = REQUEST;
							
							if(!strcmp((char*)value, "RESULT"))
								new_msg->m_type = RESULT;
			
						} else if((!strcmp((char*)name, "threadTrace"))) {
							new_msg->thread_trace = atoi( (char*) value );
			
						} else if((!strcmp((char*)name, "protocol"))) {
							new_msg->protocol = atoi( (char*) value );
						}
	
						xmlFree(value);
					}
					xmlFree(name);
				}
			}
	
			/* we're a domainObject */
			if( !strcmp((char*)cur_node->name,"domainObject" )) {
	
				name = xmlGetProp( cur_node, BAD_CAST "name");
	
				if(name) {
	
					if( !strcmp(name,"oilsMethod") ) {
	
						xmlNodePtr meth_node = cur_node->children;
	
						while( meth_node != NULL ) {
	
							if( !strcmp((char*)meth_node->name,"domainObjectAttr" )) {
								char* meth_name = xmlGetProp( meth_node, BAD_CAST "value" );
								if(meth_name) {
									new_msg->method_name = strdup(meth_name);
									xmlFree(meth_name);
								}
							}
	
							if( !strcmp((char*)meth_node->name,"params" ) && meth_node->children->content ) 
								new_msg->params = json_object_new_string( meth_node->children->content );
								//new_msg->params = json_tokener_parse(ng(json_params));
	
							meth_node = meth_node->next;
						}
					} //oilsMethod
	
					if( !strcmp(name,"oilsResult") || new_msg->m_type == STATUS ) {
	
						xmlNodePtr result_nodes = cur_node->children;
	
						while( result_nodes ) {
	
							if(!strcmp(result_nodes->name,"domainObjectAttr")) {
	
								xmlChar* result_attr_name = xmlGetProp( result_nodes, BAD_CAST "name");
								if(result_attr_name) {
									xmlChar* result_attr_value = xmlGetProp( result_nodes, BAD_CAST "value" );
	
									if( result_attr_value ) {
										if((!strcmp((char*)result_attr_name, "status"))) 
											new_msg->status_text = strdup((char*) result_attr_value );
	
										else if((!strcmp((char*)result_attr_name, "statusCode"))) 
											new_msg->status_code = atoi((char*) result_attr_value );
										xmlFree(result_attr_value);
									}
	
									xmlFree(result_attr_name);
								}
	
							}
						
	
							if(!strcmp(result_nodes->name,"domainObject")) {
								xmlChar* r_name = xmlGetProp( result_nodes, BAD_CAST "name" );
								if(r_name) {
									if( !strcmp((char*)r_name,"oilsScalar") && result_nodes->children->content ) 
										new_msg->result_content = json_object_new_string( result_nodes->children->content );
									xmlFree(r_name);
								}
							}
							result_nodes = result_nodes->next;
						}
					}
					
					if( new_msg->m_type == STATUS ) { new_msg->status_name = strdup(name); }
					xmlFree(name);
				}
			}
	
			/* we're a params node */
			if( !strcmp((char*)cur_node->name,"params" )) {
	
			}
	
			cur_node = cur_node->next;
		}
	
		msgs[msg_index] = new_msg;
		msg_index++;
		message_node = message_node->next;

	} // while message_node != null

	xmlCleanupCharEncodingHandlers();
	xmlFreeDoc( doc );
	xmlCleanupParser();

	return msg_index;

}


