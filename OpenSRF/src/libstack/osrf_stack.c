#include "osrf_stack.h"

osrf_message* _do_client( osrf_app_session*, osrf_message* );
osrf_message* _do_server( osrf_app_session*, osrf_message* );

/* tell osrf_app_session where the stack entry is */
int (*osrf_stack_entry_point) (transport_client*, int)  = &osrf_stack_process;

int osrf_stack_process( transport_client* client, int timeout ) {
	transport_message* msg = client_recv( client, timeout );
	if(msg == NULL) return 0;
	debug_handler( "Received message from transport code from %s", msg->sender );
	int status = osrf_stack_transport_handler( msg );

	while(1) {
		transport_message* m = client_recv( client, 0 );
		if(m) {
			debug_handler( "Received additional message from transport code");
			status = osrf_stack_transport_handler( m );
		} else  {
			debug_handler( "osrf_stack_process returning with only 1 received message" );
			break;
		}
	}

	return status;
}



// -----------------------------------------------------------------------------
// Entry point into the stack
// -----------------------------------------------------------------------------
int osrf_stack_transport_handler( transport_message* msg ) { 

	debug_handler( "Transport handler received new message \nfrom %s "
			"to %s with body \n\n%s\n", msg->sender, msg->recipient, msg->body );

	osrf_app_session* session = osrf_app_session_find_session( msg->thread );

	if( session == NULL ) {  /* we must be a server, build a new session */
		info_handler( "Received message for nonexistant session. Dropping..." );
		//osrf_app_server_session_init( msg->thread, 
		message_free( msg );
		return 1;
	}

	debug_handler("Session [%s] found, building message", msg->thread );

	osrf_app_session_set_remote( session, msg->sender );
	osrf_message* arr[OSRF_MAX_MSGS_PER_PACKET];
	memset(arr, 0, OSRF_MAX_MSGS_PER_PACKET );
	int num_msgs = osrf_message_deserialize(msg->body, arr, OSRF_MAX_MSGS_PER_PACKET);

	debug_handler( "We received %d messages from %s", num_msgs, msg->sender );

	/* XXX ERROR CHECKING, BAD JSON, ETC... */
	int i;
	for( i = 0; i != num_msgs; i++ ) {

		/* if we've received a jabber layer error message (probably talking to 
			someone who no longer exists) and we're not talking to the original
			remote id for this server, consider it a redirect and pass it up */
		if(msg->is_error) {
			warning_handler( " !!! Received Jabber layer error message" ); 

			if(strcmp(session->remote_id,session->orig_remote_id)) {
				warning_handler( "Treating jabber error as redirect for tt [%d] "
					"and session [%s]", arr[i]->thread_trace, session->session_id );

				arr[i]->m_type = STATUS;
				arr[i]->status_code = OSRF_STATUS_REDIRECTED;

			} else {
				warning_handler(" * Jabber Error is for top level remote id [%s], no one "
						"to send my message too!!!", session->remote_id );
			}
		}

		osrf_stack_message_handler( session, arr[i] );
	}

	message_free( msg );
	debug_handler("after msg delete");

	return 1;
}

int osrf_stack_message_handler( osrf_app_session* session, osrf_message* msg ) {
	if(session == NULL || msg == NULL)
		return 0;

	osrf_message* ret_msg = NULL;
	if( session->type ==  OSRF_SESSION_CLIENT )
		 ret_msg = _do_client( session, msg );
	else
		ret_msg= _do_server( session, msg );

	if(ret_msg)
		osrf_stack_application_handler( session, ret_msg );
	else
		osrf_message_free(msg);

	return 1;

} 

/** If we return a message, that message should be passed up the stack, 
  * if we return NULL, we're finished for now...
  */
osrf_message* _do_client( osrf_app_session* session, osrf_message* msg ) {
	if(session == NULL || msg == NULL)
		return NULL;

	osrf_message* new_msg;

	if( msg->m_type == STATUS ) {
		
		switch( msg->status_code ) {

			case OSRF_STATUS_OK:
				debug_handler("We connected successfully");
				session->state = OSRF_SESSION_CONNECTED;
				debug_handler( "State: %x => %s => %d", session, session->session_id, session->state );
				return NULL;

			case OSRF_STATUS_COMPLETE:
				osrf_app_session_set_complete( session, msg->thread_trace );
				return NULL;

			case OSRF_STATUS_CONTINUE:
				osrf_app_session_request_reset_timeout( session, msg->thread_trace );
				return NULL;

			case OSRF_STATUS_REDIRECTED:
				osrf_app_session_reset_remote( session );
				session->state = OSRF_SESSION_DISCONNECTED;
				osrf_app_session_request_resend( session, msg->thread_trace );
				return NULL;

			case OSRF_STATUS_EXPFAILED: 
				osrf_app_session_reset_remote( session );
				session->state = OSRF_SESSION_DISCONNECTED;
				osrf_app_session_request_resend( session, msg->thread_trace );
				return NULL;

			case OSRF_STATUS_TIMEOUT:
				osrf_app_session_reset_remote( session );
				session->state = OSRF_SESSION_DISCONNECTED;
				osrf_app_session_request_resend( session, msg->thread_trace );
				return NULL;


			default:
				new_msg = osrf_message_init( RESULT, msg->thread_trace, msg->protocol );
				osrf_message_set_status_info( new_msg, 
						msg->status_name, msg->status_text, msg->status_code );
				warning_handler("The stack doesn't know what to do with " 
						"the provided message code: %d, name %s. Passing UP.", 
						msg->status_code, msg->status_name );
				new_msg->is_exception = 1;
				osrf_app_session_set_complete( session, msg->thread_trace );
				osrf_message_free(msg);
				return new_msg;
		}

		return NULL;

	} else if( msg->m_type == RESULT ) 
		return msg;

	return NULL;

}


/** If we return a message, that message should be passed up the stack, 
  * if we return NULL, we're finished for now...
  */
osrf_message* _do_server( osrf_app_session* session, osrf_message* msg ) {
	if(session == NULL || msg == NULL)
		return NULL;


	if( msg->m_type == STATUS ) { return NULL; }

	warning_handler( "We dont' do servers yet !!" );

	return msg;
}




int osrf_stack_application_handler( osrf_app_session* session, osrf_message* msg ) {
	if(session == NULL || msg == NULL)
		return 0;

	if(msg->m_type == RESULT) {
		osrf_app_session_push_queue( session, msg ); 
		return 1;
	}

	warning_handler( "application_handler can't handle whatever you sent, type %d", msg->m_type);

	return 1;

}
