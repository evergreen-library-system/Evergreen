#include "transport_session.h"



// ---------------------------------------------------------------------------------
// returns a built and allocated transport_session object.
// This codes does no network activity, only memory initilization
// ---------------------------------------------------------------------------------
transport_session* init_transport(  char* server, int port, void* user_data, int component ) {

	/* create the session struct */
	transport_session* session = 
		(transport_session*) safe_malloc( sizeof(transport_session) );

	session->user_data = user_data;

	session->component = component;

	/* initialize the data buffers */
	session->body_buffer			= buffer_init( JABBER_BODY_BUFSIZE );
	session->subject_buffer		= buffer_init( JABBER_SUBJECT_BUFSIZE );
	session->thread_buffer		= buffer_init( JABBER_THREAD_BUFSIZE );
	session->from_buffer			= buffer_init( JABBER_JID_BUFSIZE );
	session->status_buffer		= buffer_init( JABBER_STATUS_BUFSIZE );
	session->recipient_buffer	= buffer_init( JABBER_JID_BUFSIZE );
	session->message_error_type = buffer_init( JABBER_JID_BUFSIZE );
	session->session_id			= buffer_init( 64 ); 

	/* for OpenSRF extensions */
	session->router_to_buffer		= buffer_init( JABBER_JID_BUFSIZE );
	session->router_from_buffer	= buffer_init( JABBER_JID_BUFSIZE );
	session->router_class_buffer	= buffer_init( JABBER_JID_BUFSIZE );
	session->router_command_buffer	= buffer_init( JABBER_JID_BUFSIZE );


	if(	session->body_buffer		== NULL || session->subject_buffer	 == NULL	||
			session->thread_buffer	== NULL || session->from_buffer		 == NULL	||
			session->status_buffer	== NULL || session->recipient_buffer == NULL ||
			session->router_to_buffer	== NULL || session->router_from_buffer	 == NULL ||
			session->router_class_buffer == NULL || session->router_command_buffer == NULL ||
			session->session_id == NULL ) { 

		fatal_handler( "init_transport(): buffer_init returned NULL" );
		return 0;
	}


	/* initialize the jabber state machine */
	session->state_machine = (jabber_machine*) safe_malloc( sizeof(jabber_machine) );

	/* initialize the sax push parser */
	session->parser_ctxt = xmlCreatePushParserCtxt(SAXHandler, session, "", 0, NULL);

	/* initialize the transport_socket structure */
	session->sock_obj = (transport_socket*) safe_malloc( sizeof(transport_socket) );

	//int serv_size = strlen( server );
	session->sock_obj->server = server;
	session->sock_obj->port = port;
	session->sock_obj->data_received_callback = &grab_incoming;

	/* this will be handed back to us in callbacks */
	session->sock_obj->user_data = session; 

	return session;
}



/* XXX FREE THE BUFFERS */
int session_free( transport_session* session ) {
	if( ! session ) { return 0; }

	if( session->sock_obj ) 
		free( session->sock_obj );

	if( session->state_machine ) free( session->state_machine );
	if( session->parser_ctxt) {
		xmlCleanupCharEncodingHandlers();
		xmlFreeDoc( session->parser_ctxt->myDoc );
		xmlFreeParserCtxt(session->parser_ctxt);
	}
	xmlCleanupParser();

	buffer_free(session->body_buffer);
	buffer_free(session->subject_buffer);
	buffer_free(session->thread_buffer);
	buffer_free(session->from_buffer);
	buffer_free(session->recipient_buffer);
	buffer_free(session->status_buffer);
	buffer_free(session->message_error_type);
	buffer_free(session->router_to_buffer);
	buffer_free(session->router_from_buffer);
	buffer_free(session->router_class_buffer);
	buffer_free(session->router_command_buffer);
	buffer_free(session->session_id);


	free( session );
	return 1;
}


int session_wait( transport_session* session, int timeout ) {
	if( ! session || ! session->sock_obj ) {
		return 0;
	}
	int ret =  tcp_wait( session->sock_obj, timeout );
	if( ! ret ) {
		session->state_machine->connected = 0;
	}
	return ret;
}

int session_send_msg( 
		transport_session* session, transport_message* msg ) {

	if( ! session ) { return 0; }

	if( ! session->state_machine->connected ) {
		warning_handler("State machine is not connected in send_msg()");
		return 0;
	}

	message_prepare_xml( msg );
	tcp_send( session->sock_obj, msg->msg_xml );

	return 1;

}


/* connects to server and connects to jabber */
int session_connect( transport_session* session, 
		const char* username, const char* password, 
		const char* resource, int connect_timeout, enum TRANSPORT_AUTH_TYPE auth_type ) {

	int size1 = 0;
	int size2 = 0;

	if( ! session ) { 
		warning_handler( "session is null in connect" );
		return 0; 
	}


	char* server = session->sock_obj->server;

	if( ! session->sock_obj ) {
		return 0;
	}

	if( ! session->sock_obj->connected ) {
		if( ! tcp_connect( session->sock_obj ))
			return 0;
	}

	if( session->component ) {

		/* the first Jabber connect stanza */
		char* our_hostname = getenv("HOSTNAME");
		size1 = 150 + strlen( server );
		char stanza1[ size1 ]; 
		memset( stanza1, 0, size1 );
		sprintf( stanza1, 
				"<stream:stream version='1.0' xmlns:stream='http://etherx.jabber.org/streams' "
				"xmlns='jabber:component:accept' to='%s' from='%s' xml:lang='en'>",
				username, our_hostname );

		/* send the first stanze */
		session->state_machine->connecting = CONNECTING_1;
		if( ! tcp_send( session->sock_obj, stanza1 ) ) {
			warning_handler("error sending");
			return 0;
		}
	
		/* wait for reply */
		tcp_wait( session->sock_obj, connect_timeout ); /* make the timeout smarter XXX */
	
		/* server acknowledges our existence, now see if we can login */
		if( session->state_machine->connecting == CONNECTING_2 ) {
	
			int ss = session->session_id->n_used + strlen(password) + 5;
			char hashstuff[ss];
			memset(hashstuff,0,ss);
			sprintf( hashstuff, "%s%s", session->session_id->buf, password );

			char* hash = shahash( hashstuff );
			size2 = 100 + strlen( hash );
			char stanza2[ size2 ];
			memset( stanza2, 0, size2 );
			sprintf( stanza2, "<handshake>%s</handshake>", hash );
	
			if( ! tcp_send( session->sock_obj, stanza2 )  ) {
				warning_handler("error sending");
				return 0;
			}
		}

	} else { /* we're not a component */

		/* the first Jabber connect stanza */
		size1 = 100 + strlen( server );
		char stanza1[ size1 ]; 
		memset( stanza1, 0, size1 );
		sprintf( stanza1, 
				"<stream:stream to='%s' xmlns='jabber:client' "
				"xmlns:stream='http://etherx.jabber.org/streams'>",
			server );
	

		/* send the first stanze */
		session->state_machine->connecting = CONNECTING_1;
		if( ! tcp_send( session->sock_obj, stanza1 ) ) {
			warning_handler("error sending");
			return 0;
		}


		/* wait for reply */
		tcp_wait( session->sock_obj, connect_timeout ); /* make the timeout smarter XXX */

		if( auth_type == AUTH_PLAIN ) {

			/* the second jabber connect stanza including login info*/
			size2 = 150 + strlen( username ) + strlen(password) + strlen(resource);
			char stanza2[ size2 ];
			memset( stanza2, 0, size2 );
		
			sprintf( stanza2, 
					"<iq id='123456789' type='set'><query xmlns='jabber:iq:auth'>"
					"<username>%s</username><password>%s</password><resource>%s</resource></query></iq>",
					username, password, resource );
	
			/* server acknowledges our existence, now see if we can login */
			if( session->state_machine->connecting == CONNECTING_2 ) {
				if( ! tcp_send( session->sock_obj, stanza2 )  ) {
					warning_handler("error sending");
					return 0;
				}
			}

		} else if( auth_type == AUTH_DIGEST ) {

			int ss = session->session_id->n_used + strlen(password) + 5;
			char hashstuff[ss];
			memset(hashstuff,0,ss);
			sprintf( hashstuff, "%s%s", session->session_id->buf, password );

			char* hash = shahash( hashstuff );

			/* the second jabber connect stanza including login info*/
			size2 = 150 + strlen( hash ) + strlen(password) + strlen(resource);
			char stanza2[ size2 ];
			memset( stanza2, 0, size2 );
		
			sprintf( stanza2, 
					"<iq id='123456789' type='set'><query xmlns='jabber:iq:auth'>"
					"<username>%s</username><digest>%s</digest><resource>%s</resource></query></iq>",
					username, hash, resource );
	
			/* server acknowledges our existence, now see if we can login */
			if( session->state_machine->connecting == CONNECTING_2 ) {
				if( ! tcp_send( session->sock_obj, stanza2 )  ) {
					warning_handler("error sending");
					return 0;
				}
			}

		}

	} // not component


	/* wait for reply */
	tcp_wait( session->sock_obj, connect_timeout );

	if( session->state_machine->connected ) {
		/* yar! */
		return 1;
	}

	return 0;
}

// ---------------------------------------------------------------------------------
// TCP data callback. Shove the data into the push parser.
// ---------------------------------------------------------------------------------
void grab_incoming( void * session, char* data ) {
	transport_session* ses = (transport_session*) session;
	if( ! ses ) { return; }
	debug_handler("Parsing incoming XML chunk");
	xmlParseChunk(ses->parser_ctxt, data, strlen(data), 0);
	debug_handler("Completed parsing incoming XML chunk");
}


void startElementHandler(
	void *session, const xmlChar *name, const xmlChar **atts) {

	transport_session* ses = (transport_session*) session;
	if( ! ses ) { return; }

	
	if( strcmp( name, "message" ) == 0 ) {
		ses->state_machine->in_message = 1;
		buffer_add( ses->from_buffer, get_xml_attr( atts, "from" ) );
		buffer_add( ses->recipient_buffer, get_xml_attr( atts, "to" ) );
		buffer_add( ses->router_from_buffer, get_xml_attr( atts, "router_from" ) );
		buffer_add( ses->router_to_buffer, get_xml_attr( atts, "router_to" ) );
		buffer_add( ses->router_class_buffer, get_xml_attr( atts, "router_class" ) );
		buffer_add( ses->router_command_buffer, get_xml_attr( atts, "router_command" ) );
		char* broadcast = get_xml_attr( atts, "broadcast" );
		if( broadcast )
			ses->router_broadcast = atoi( broadcast );

		return;
	}

	if( ses->state_machine->in_message ) {

		if( strcmp( name, "body" ) == 0 ) {
			ses->state_machine->in_message_body = 1;
			return;
		}
	
		if( strcmp( name, "subject" ) == 0 ) {
			ses->state_machine->in_subject = 1;
			return;
		}
	
		if( strcmp( name, "thread" ) == 0 ) {
			ses->state_machine->in_thread = 1;
			return;
		}

	}

	if( strcmp( name, "presence" ) == 0 ) {
		ses->state_machine->in_presence = 1;
		buffer_add( ses->from_buffer, get_xml_attr( atts, "from" ) );
		buffer_add( ses->recipient_buffer, get_xml_attr( atts, "to" ) );
		return;
	}

	if( strcmp( name, "status" ) == 0 ) {
		ses->state_machine->in_status = 1;
		return;
	}


	if( strcmp( name, "stream:error" ) == 0 ) {
		ses->state_machine->in_error = 1;
		warning_handler( "Received <stream:error> message from Jabber server" );
		return;
	}


	/* first server response from a connect attempt */
	if( strcmp( name, "stream:stream" ) == 0 ) {
		if( ses->state_machine->connecting == CONNECTING_1 ) {
			ses->state_machine->connecting = CONNECTING_2;
			buffer_add( ses->session_id, get_xml_attr(atts, "id") );
		}
	}

	if( strcmp( name, "handshake" ) == 0 ) {
		ses->state_machine->connected = 1;
		ses->state_machine->connecting = 0;
		return;
	}


	if( strcmp( name, "error" ) == 0 ) {
		ses->state_machine->in_message_error = 1;
		buffer_add( ses->message_error_type, get_xml_attr( atts, "type" ) );
		ses->message_error_code = atoi( get_xml_attr( atts, "code" ) );
		warning_handler( "Received <error> message" );
		return;
	}

	if( strcmp( name, "iq" ) == 0 ) {
		ses->state_machine->in_iq = 1;

		if( strcmp( get_xml_attr(atts, "type"), "result") == 0 
				&& ses->state_machine->connecting == CONNECTING_2 ) {
			ses->state_machine->connected = 1;
			ses->state_machine->connecting = 0;
			return;
		}

		if( strcmp( get_xml_attr(atts, "type"), "error") == 0 ) {
			warning_handler( "Error connecting to jabber" );
			return;
		}
	}
}

char* get_xml_attr( const xmlChar** atts, char* attr_name ) {
	int i;
	if (atts != NULL) {
		for(i = 0;(atts[i] != NULL);i++) {
			if( strcmp( atts[i++], attr_name ) == 0 ) {
				if( atts[i] != NULL ) {
					return (char*) atts[i];
				}
			}
		}
	}
	return NULL;
}


// ------------------------------------------------------------------
// See which tags are ending
// ------------------------------------------------------------------
void endElementHandler( void *session, const xmlChar *name) {
	transport_session* ses = (transport_session*) session;
	if( ! ses ) { return; }

	if( strcmp( name, "message" ) == 0 ) {


		/* pass off the message info the callback */
		if( ses->message_callback ) {

			/* here it's ok to pass in the raw buffers because
				message_init allocates new space for the chars 
				passed in */
			transport_message* msg =  message_init( 
				ses->body_buffer->buf, 
				ses->subject_buffer->buf,
				ses->thread_buffer->buf, 
				ses->recipient_buffer->buf, 
				ses->from_buffer->buf );

			message_set_router_info( msg, 
				ses->router_from_buffer->buf, 
				ses->router_to_buffer->buf, 
				ses->router_class_buffer->buf,
				ses->router_command_buffer->buf,
				ses->router_broadcast );

			if( ses->message_error_type->n_used > 0 ) {
				set_msg_error( msg, ses->message_error_type->buf, ses->message_error_code );
			}

			if( msg == NULL ) { return; }
			ses->message_callback( ses->user_data, msg );
		}

		ses->state_machine->in_message = 0;
		reset_session_buffers( session );
		return;
	}
	
	if( strcmp( name, "body" ) == 0 ) {
		ses->state_machine->in_message_body = 0;
		return;
	}

	if( strcmp( name, "subject" ) == 0 ) {
		ses->state_machine->in_subject = 0;
		return;
	}

	if( strcmp( name, "thread" ) == 0 ) {
		ses->state_machine->in_thread = 0;
		return;
	}
	
	if( strcmp( name, "iq" ) == 0 ) {
		ses->state_machine->in_iq = 0;
		if( ses->message_error_code > 0 ) {
			warning_handler( "Error in IQ packet: code %d",  ses->message_error_code );
			warning_handler( "Error 401 means not authorized" );
		}
		reset_session_buffers( session );
		return;
	}

	if( strcmp( name, "presence" ) == 0 ) {
		ses->state_machine->in_presence = 0;
		/*
		if( ses->presence_callback ) {
			// call the callback with the status, etc.
		}
		*/
		reset_session_buffers( session );
		return;
	}

	if( strcmp( name, "status" ) == 0 ) {
		ses->state_machine->in_status = 0;
		return;
	}

	if( strcmp( name, "error" ) == 0 ) {
		ses->state_machine->in_message_error = 0;
		return;
	}

	if( strcmp( name, "error:error" ) == 0 ) {
		ses->state_machine->in_error = 0;
		return;
	}
}

int reset_session_buffers( transport_session* ses ) {
	buffer_reset( ses->body_buffer );
	buffer_reset( ses->subject_buffer );
	buffer_reset( ses->thread_buffer );
	buffer_reset( ses->from_buffer );
	buffer_reset( ses->recipient_buffer );
	buffer_reset( ses->router_from_buffer );
	buffer_reset( ses->router_to_buffer );
	buffer_reset( ses->router_class_buffer );
	buffer_reset( ses->router_command_buffer );
	buffer_reset( ses->message_error_type );
	buffer_reset( ses->session_id );

	return 1;
}

// ------------------------------------------------------------------
// takes data out of the body of the message and pushes it into
// the appropriate buffer
// ------------------------------------------------------------------
void characterHandler(
		void *session, const xmlChar *ch, int len) {

	char data[len+1];
	memset( data, 0, len+1 );
	strncpy( data, (char*) ch, len );
	data[len] = 0;

	//printf( "Handling characters: %s\n", data );
	transport_session* ses = (transport_session*) session;
	if( ! ses ) { return; }

	/* set the various message parts */
	if( ses->state_machine->in_message ) {

		if( ses->state_machine->in_message_body ) {
			buffer_add( ses->body_buffer, data );
		}

		if( ses->state_machine->in_subject ) {
			buffer_add( ses->subject_buffer, data );
		}

		if( ses->state_machine->in_thread ) {
			buffer_add( ses->thread_buffer, data );
		}
	}

	/* set the presence status */
	if( ses->state_machine->in_presence && ses->state_machine->in_status ) {
		buffer_add( ses->status_buffer, data );
	}

	if( ses->state_machine->in_error ) {
		/* for now... */
		warning_handler( "ERROR Xml fragment: %s\n", ch );
	}

}

/* XXX change to warning handlers */
void  parseWarningHandler( void *session, const char* msg, ... ) {

	va_list args;
	va_start(args, msg);
	fprintf(stdout, "transport_session XML WARNING");
	vfprintf(stdout, msg, args);
	va_end(args);
	fprintf(stderr, "XML WARNING: %s\n", msg ); 
}

void  parseErrorHandler( void *session, const char* msg, ... ){

	va_list args;
	va_start(args, msg);
	fprintf(stdout, "transport_session XML ERROR");
	vfprintf(stdout, msg, args);
	va_end(args);
	fprintf(stderr, "XML ERROR: %s\n", msg ); 

}

int session_disconnect( transport_session* session ) {
	if( session == NULL ) { return 0; }
	tcp_send( session->sock_obj, "</stream:stream>");
	return tcp_disconnect( session->sock_obj );
}

