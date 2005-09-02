#include "transport_message.h"


// ---------------------------------------------------------------------------------
// Allocates and initializes a new transport_message
// ---------------------------------------------------------------------------------
transport_message* message_init( char* body, 
		char* subject, char* thread, char* recipient, char* sender ) {

	transport_message* msg = 
		(transport_message*) safe_malloc( sizeof(transport_message) );

	if( body					== NULL ) { body			= ""; }
	if( thread				== NULL ) { thread		= ""; }
	if( subject				== NULL ) { subject		= ""; }
	if( sender				== NULL ) { sender		= ""; }
	if( recipient			==	NULL ) { recipient	= ""; }

	msg->body				= strdup(body);
	msg->thread				= strdup(thread);
	msg->subject			= strdup(subject);
	msg->recipient			= strdup(recipient);
	msg->sender				= strdup(sender);

	if(	msg->body		== NULL || msg->thread				== NULL	||
			msg->subject	== NULL || msg->recipient			== NULL	||
			msg->sender		== NULL ) {

		fatal_handler( "message_init(): Out of Memory" );
		return NULL;
	}

	return msg;
}


transport_message* new_message_from_xml( const char* msg_xml ) {

	if( msg_xml == NULL || strlen(msg_xml) < 1 )
		return NULL;

	transport_message* new_msg = 
		(transport_message*) safe_malloc( sizeof(transport_message) );

	xmlKeepBlanksDefault(0);
	xmlDocPtr msg_doc = xmlReadDoc( BAD_CAST msg_xml, NULL, NULL, 0 );
	xmlNodePtr root = xmlDocGetRootElement(msg_doc);

	xmlChar* sender	= xmlGetProp(root, BAD_CAST "from");
	xmlChar* recipient	= xmlGetProp(root, BAD_CAST "to");
	xmlChar* subject		= xmlGetProp(root, BAD_CAST "subject");
	xmlChar* thread		= xmlGetProp( root, BAD_CAST "thread" );
	xmlChar* router_from	= xmlGetProp( root, BAD_CAST "router_from" );
	xmlChar* router_to	= xmlGetProp( root, BAD_CAST "router_to" );
	xmlChar* router_class= xmlGetProp( root, BAD_CAST "router_class" );
	xmlChar* broadcast	= xmlGetProp( root, BAD_CAST "broadcast" );

	if( router_from ) {
		new_msg->sender		= strdup((char*)router_from);
	} else {
		if( sender ) {
			new_msg->sender		= strdup((char*)sender);
			xmlFree(sender);
		}
	}

	if( recipient ) {
		new_msg->recipient	= strdup((char*)recipient);
		xmlFree(recipient);
	}
	if(subject){
		new_msg->subject		= strdup((char*)subject);
		xmlFree(subject);
	}
	if(thread) {
		new_msg->thread		= strdup((char*)thread);
		xmlFree(thread);
	}
	if(router_from) {
		new_msg->router_from	= strdup((char*)router_from);
		xmlFree(router_from);
	}
	if(router_to) {
		new_msg->router_to	= strdup((char*)router_to);
		xmlFree(router_to);
	}
	if(router_class) {
		new_msg->router_class = strdup((char*)router_class);
		xmlFree(router_class);
	}
	if(broadcast) {
		if(strcmp(broadcast,"0") )
			new_msg->broadcast	= 1;
		xmlFree(broadcast);
	}

	xmlNodePtr search_node = root->children;
	while( search_node != NULL ) {

		if( ! strcmp( (char*) search_node->name, "thread" ) ) {
			if( search_node->children && search_node->children->content ) 
				new_msg->thread = strdup( (char*) search_node->children->content );
		}

		if( ! strcmp( (char*) search_node->name, "subject" ) ) {
			if( search_node->children && search_node->children->content )
				new_msg->subject = strdup( (char*) search_node->children->content );
		}

		if( ! strcmp( (char*) search_node->name, "body" ) ) {
			if( search_node->children && search_node->children->content )
				new_msg->body = strdup((char*) search_node->children->content );
		}

		search_node = search_node->next;
	}

	if( new_msg->thread == NULL ) 
		new_msg->thread = strdup("");
	if( new_msg->subject == NULL )
		new_msg->subject = strdup("");
	if( new_msg->body == NULL )
		new_msg->body = strdup("");

	int			bufsize;
	xmlChar*		xmlbuf;
	char*			encoded_body;

	xmlDocDumpFormatMemory( msg_doc, &xmlbuf, &bufsize, 0 );
	encoded_body = strdup( (char*) xmlbuf );

	if( encoded_body == NULL ) 
		fatal_handler("message_to_xml(): Out of Memory");

	xmlFree(xmlbuf);
	xmlFreeDoc(msg_doc);
	xmlCleanupParser();

	/*** remove the XML declaration */
	int len = strlen(encoded_body);
	char tmp[len];
	memset( tmp, 0, len );
	int i;
	int found_at = 0;

	/* when we reach the first >, take everything after it */
	for( i = 0; i!= len; i++ ) {
		if( encoded_body[i] == 62) { /* ascii > */

			/* found_at holds the starting index of the rest of the doc*/
			found_at = i + 1; 
			break;
		}
	}

	if( found_at ) {
		/* move the shortened doc into the tmp buffer */
		strncpy( tmp, encoded_body + found_at, len - found_at );
		/* move the tmp buffer back into the allocated space */
		memset( encoded_body, 0, len );
		strcpy( encoded_body, tmp );
	}

	new_msg->msg_xml = encoded_body;
	return new_msg;

}


void message_set_router_info( transport_message* msg, char* router_from,
		char* router_to, char* router_class, char* router_command, int broadcast_enabled ) {

	if(router_from)
		msg->router_from		= strdup(router_from);
	else
		msg->router_from		= strdup("");

	if(router_to)
		msg->router_to			= strdup(router_to);
	else
		msg->router_to			= strdup("");

	if(router_class)
		msg->router_class		= strdup(router_class);
	else 
		msg->router_class		= strdup("");
	
	if(router_command)
		msg->router_command	= strdup(router_command);
	else
		msg->router_command	= strdup("");

	msg->broadcast = broadcast_enabled;

	if( msg->router_from == NULL || msg->router_to == NULL ||
			msg->router_class == NULL || msg->router_command == NULL ) 
		fatal_handler( "message_set_router_info(): Out of Memory" );

	return;
}



/* encodes the message for traversal */
int message_prepare_xml( transport_message* msg ) {
	if( msg->msg_xml != NULL ) { return 1; }
	msg->msg_xml = message_to_xml( msg );
	return 1;
}


// ---------------------------------------------------------------------------------
//
// ---------------------------------------------------------------------------------
int message_free( transport_message* msg ){
	if( msg == NULL ) { return 0; }

	free(msg->body); 
	free(msg->thread);
	free(msg->subject);
	free(msg->recipient);
	free(msg->sender);
	free(msg->router_from);
	free(msg->router_to);
	free(msg->router_class);
	free(msg->router_command);
	if( msg->error_type != NULL ) free(msg->error_type);
	if( msg->msg_xml != NULL ) free(msg->msg_xml);
	free(msg);
	return 1;
}
	
// ---------------------------------------------------------------------------------
// Allocates a char* holding the XML representation of this jabber message
// ---------------------------------------------------------------------------------
char* message_to_xml( const transport_message* msg ) {

	int			bufsize;
	xmlChar*		xmlbuf;
	char*			encoded_body;

	xmlNodePtr	message_node;
	xmlNodePtr	body_node;
	xmlNodePtr	thread_node;
	xmlNodePtr	subject_node;
	xmlNodePtr	error_node;
	
	xmlDocPtr	doc;

	xmlKeepBlanksDefault(0);

	if( ! msg ) { 
		warning_handler( "Passing NULL message to message_to_xml()"); 
		return 0; 
	}

	doc = xmlReadDoc( BAD_CAST "<message/>", NULL, NULL, XML_PARSE_NSCLEAN );
	message_node = xmlDocGetRootElement(doc);

	if( msg->is_error ) {
		error_node = xmlNewChild(message_node, NULL, BAD_CAST "error" , NULL );
		xmlAddChild( message_node, error_node );
		xmlNewProp( error_node, BAD_CAST "type", BAD_CAST msg->error_type );
		char code_buf[16];
		memset( code_buf, 0, 16);
		sprintf(code_buf, "%d", msg->error_code );
		xmlNewProp( error_node, BAD_CAST "code", BAD_CAST code_buf  );
	}
	

	/* set from and to */
	xmlNewProp( message_node, BAD_CAST "to", BAD_CAST msg->recipient );
	xmlNewProp( message_node, BAD_CAST "from", BAD_CAST msg->sender );
	xmlNewProp( message_node, BAD_CAST "router_from", BAD_CAST msg->router_from );
	xmlNewProp( message_node, BAD_CAST "router_to", BAD_CAST msg->router_to );
	xmlNewProp( message_node, BAD_CAST "router_class", BAD_CAST msg->router_class );
	xmlNewProp( message_node, BAD_CAST "router_command", BAD_CAST msg->router_command );

	if( msg->broadcast )
		xmlNewProp( message_node, BAD_CAST "broadcast", BAD_CAST "1" );

	/* Now add nodes where appropriate */
	char* body				= msg->body;
	char* subject			= msg->subject;
	char* thread			= msg->thread; 

	if( thread && strlen(thread) > 0 ) {
		thread_node = xmlNewChild(message_node, NULL, (xmlChar*) "thread", NULL );
//		xmlNewTextChild(thread_node, NULL, NULL,  );
		xmlNodePtr txt = xmlNewText((xmlChar*) thread);
		xmlAddChild(thread_node, txt);
		xmlAddChild(message_node, thread_node); 
	}

	if( subject && strlen(subject) > 0 ) {
		subject_node = xmlNewChild(message_node, NULL, (xmlChar*) "subject", NULL );
		//xmlNewTextChild(subject_node, NULL, NULL, (xmlChar*) subject );
		xmlNodePtr txt = xmlNewText((xmlChar*) subject);
		xmlAddChild(subject_node, txt);
		xmlAddChild( message_node, subject_node ); 
	}

	if( body && strlen(body) > 0 ) {
		body_node = xmlNewChild(message_node, NULL, (xmlChar*) "body", NULL);
		//xmlNewTextChild(body_node, NULL, NULL, (xmlChar*) body );
		xmlNodePtr txt = xmlNewText((xmlChar*) body);
		xmlAddChild(body_node, txt);
		xmlAddChild( message_node, body_node ); 
	}


	/*
	xmlBufferPtr buf = xmlBufferCreate();
	int status = xmlNodeDump( buf, doc, xmlDocGetRootElement(doc) , 1, 0 ); 
	*/

	//xmlDocDumpFormatMemory( doc, &xmlbuf, &bufsize, 0 );
	xmlDocDumpMemoryEnc( doc, &xmlbuf, &bufsize, "UTF-8" );

	encoded_body = strdup( (char*) xmlbuf );

	if( encoded_body == NULL ) 
		fatal_handler("message_to_xml(): Out of Memory");

	xmlFree(xmlbuf);
	xmlFreeDoc( doc );
	xmlCleanupParser();


	/*** remove the XML declaration */
	int len = strlen(encoded_body);
	char tmp[len];
	memset( tmp, 0, len );
	int i;
	int found_at = 0;

	/* when we reach the first >, take everything after it */
	for( i = 0; i!= len; i++ ) {
		if( encoded_body[i] == 62) { /* ascii > */

			/* found_at holds the starting index of the rest of the doc*/
			found_at = i + 1; 
			break;
		}
	}

	if( found_at ) {
		/* move the shortened doc into the tmp buffer */
		strncpy( tmp, encoded_body + found_at, len - found_at );
		/* move the tmp buffer back into the allocated space */
		memset( encoded_body, 0, len );
		strcpy( encoded_body, tmp );
	}

	return encoded_body;
}



void jid_get_username( const char* jid, char buf[] ) {

	if( jid == NULL ) { return; }

	/* find the @ and return whatever is in front of it */
	int len = strlen( jid );
	int i;
	for( i = 0; i != len; i++ ) {
		if( jid[i] == 64 ) { /*ascii @*/
			strncpy( buf, jid, i );
			return;
		}
	}
}


void jid_get_resource( const char* jid, char buf[])  {
	if( jid == NULL ) { return; }
	int len = strlen( jid );
	int i;
	for( i = 0; i!= len; i++ ) {
		if( jid[i] == 47 ) { /* ascii / */
			strncpy( buf, jid + i + 1, len - (i+1) );
		}
	}
}

void jid_get_domain( const char* jid, char buf[] ) {

	if(jid == NULL) return;

	int len = strlen(jid);
	int i;
	int index1 = 0; 
	int index2 = 0;

	for( i = 0; i!= len; i++ ) {
		if(jid[i] == 64) /* ascii @ */
			index1 = i + 1;
		else if(jid[i] == 47 && index1 != 0) /* ascii / */
			index2 = i;
	}
	if( index1 > 0 && index2 > 0 && index2 > index1 )
		memcpy( buf, jid + index1, index2 - index1 );
}

void set_msg_error( transport_message* msg, char* type, int err_code ) {

	if( type != NULL && strlen( type ) > 0 ) {
		msg->error_type = safe_malloc( strlen(type)+1); 
		strcpy( msg->error_type, type );
		msg->error_code = err_code;
	}
	msg->is_error = 1;
}
