#include "osrf_app_session.h"
#include <time.h>

/* the global app_session cache */
osrf_app_session* app_session_cache;



// --------------------------------------------------------------------------
// --------------------------------------------------------------------------
// Request API
// --------------------------------------------------------------------------

/** Allocation and initializes a new app_request object */
osrf_app_request* _osrf_app_request_init( 
		osrf_app_session* session, osrf_message* msg ) {

	osrf_app_request* req = 
		(osrf_app_request*) safe_malloc(sizeof(osrf_app_request));

	req->session		= session;
	req->request_id	= msg->thread_trace;
	req->complete		= 0;
	req->payload		= msg;
	req->result			= NULL;

	return req;

}

/** Frees memory used by an app_request object */
void _osrf_app_request_free( osrf_app_request * req ){
	if( req == NULL ) return;

	if( req->payload ) {
		osrf_message_free( req->payload );
	}

	/*
	osrf_message* cur_msg = req->result;
	while( cur_msg != NULL ) {
		osrf_message* next_msg = cur_msg->next;
		osrf_message_free( cur_msg );
		cur_msg = next_msg;
	}
	osrf_message_free( req->payload );
	*/

	free( req );
	debug_handler("after request free");
}

/** Pushes the given message onto the list of 'responses' to this request */
void _osrf_app_request_push_queue( osrf_app_request* req, osrf_message* result ){
	if(req == NULL || result == NULL) return;
	debug_handler( "App Session pushing [%d] onto request queue", result->thread_trace );
	if(req->result == NULL)
		req->result = result;
	else {
		result->next = req->result;
		req->result = result;
	}
}

/** Removes this app_request from our session request set */
void osrf_app_session_request_finish( 
		osrf_app_session* session, int req_id ){

	if(session == NULL) return;
	debug_handler("Finishing request %d", req_id );
	osrf_app_request* req = _osrf_app_session_get_request( session, req_id );
	if(req == NULL) return;
	_osrf_app_session_remove_request( req->session, req );
	_osrf_app_request_free( req );
}


void osrf_app_session_request_reset_timeout( osrf_app_session* session, int req_id ) {
	if(session == NULL) return;
	debug_handler("Resetting timeout %d", req_id );
	osrf_app_request* req = _osrf_app_session_get_request( session, req_id );
	if(req == NULL) return;
	req->reset_timeout = 1;
}

/** Checks the receive queue for messages.  If any are found, the first
  * is popped off and returned.  Otherwise, this method will wait at most timeout 
  * seconds for a message to appear in the receive queue.  Once it arrives it is returned.
  * If no messages arrive in the timeout provided, null is returned.
  */
osrf_message* _osrf_app_request_recv( osrf_app_request* req, int timeout ) {

	if(req == NULL) return NULL;

	if( req->result != NULL ) {
		debug_handler("app_request receive already has a message, returning it");
		/* pop off the first message in the list */
		osrf_message* tmp_msg = req->result;
		req->result = req->result->next;
		return tmp_msg;
	}

	time_t start = time(NULL);	
	time_t remaining = (time_t) timeout;

	while( remaining >= 0 ) {
		/* tell the session to wait for stuff */
		debug_handler( "In app_request receive with remaining time [%d]", (int) remaining );

		osrf_app_session_queue_wait( req->session, 0 );

		if( req->result != NULL ) { /* if we received anything */
			/* pop off the first message in the list */
			debug_handler( "app_request_recv received a message, returning it");
			osrf_message* ret_msg = req->result;
			osrf_message* tmp_msg = ret_msg->next;
			req->result = tmp_msg;
			return ret_msg;
		}

		if( req->complete )
			return NULL;

		osrf_app_session_queue_wait( req->session, (int) remaining );

		if( req->result != NULL ) { /* if we received anything */
			/* pop off the first message in the list */
			debug_handler( "app_request_recv received a message, returning it");
			osrf_message* ret_msg = req->result;
			osrf_message* tmp_msg = ret_msg->next;
			req->result = tmp_msg;
			return ret_msg;
		}
		if( req->complete )
			return NULL;

		if(req->reset_timeout) {
			remaining = (time_t) timeout;
			req->reset_timeout = 0;
			debug_handler("Recevied a timeout reset");
		} else {
			remaining -= (int) (time(NULL) - start);
		}
	}

	debug_handler("Returning NULL from app_request_recv after timeout");
	return NULL;
}

/** Resend this requests original request message */
int _osrf_app_request_resend( osrf_app_request* req ) {
	if(req == NULL) return 0;
	if(!req->complete) {
		debug_handler( "Resending request [%d]", req->request_id );
		return _osrf_app_session_send( req->session, req->payload );
	}
	return 1;
}



// --------------------------------------------------------------------------
// --------------------------------------------------------------------------
// Session API
// --------------------------------------------------------------------------

/** returns a session from the global session hash */
osrf_app_session* osrf_app_session_find_session( char* session_id ) {
	osrf_app_session* ptr = app_session_cache;
	debug_handler("Searching for session in global cache with id [%s]", session_id );
	while( ptr != NULL ) {
		if( !strcmp(ptr->session_id,session_id) )
			return ptr;
		ptr = ptr->next;
	}
	return NULL;
}


/** adds a session to the global session cache */
void _osrf_app_session_push_session( osrf_app_session* session ) {

	if( app_session_cache == NULL ) {
		app_session_cache = session;
		return;
	}

	osrf_app_session* ptr = app_session_cache;
	debug_handler( "Pushing [%s] [%s] onto global session cache", 
			session->remote_service, session->session_id );
	while( ptr != NULL ) {
		if( !strcmp(ptr->session_id, session->session_id) )
			return;
		if( ptr->next == NULL ) {
			ptr->next = session;
			return;
		}
		ptr = ptr->next;
	}
}


/** unlinks from global session cache */
void _osrf_app_session_remove_session( char* session_id ) {

	if( app_session_cache == NULL )
		return;

	debug_handler( "App Session removing session [%s] from global cache", session_id );
	if( !strcmp(app_session_cache->session_id, session_id) ) {
		if( app_session_cache->next != NULL ) {
			osrf_app_session* next = app_session_cache->next;
			app_session_cache = next;
			return;
		} else {
			app_session_cache = NULL;
			return;
		}
	}

	if( app_session_cache->next == NULL )
		return;

	osrf_app_session* prev = app_session_cache;
	osrf_app_session* ptr = prev->next;
	while( ptr != NULL ) {
		if( ptr->session_id == session_id ) {
			osrf_app_session* tmp = ptr->next;
			prev->next = tmp;
			return;
		}
		ptr = ptr->next;
	}
}

/** Allocates a initializes a new app_session */

osrf_app_session* osrf_app_client_session_init( char* remote_service ) {

	osrf_app_session* session = safe_malloc(sizeof(osrf_app_session));	

	session->transport_handle = osrf_system_get_transport_client();
	if( session->transport_handle == NULL ) {
		warning_handler("No transport client for service 'client'");
		return NULL;
	}

	char target_buf[512];
	memset(target_buf,0,512);
	char* domain	= config_value( "opensrf.bootstrap", "//bootstrap/domains/domain1" ); /* just the first for now */
	char* router_name = config_value( "opensrf.bootstrap", "//bootstrap/router_name" );
	sprintf( target_buf, "%s@%s/%s",  router_name, domain, remote_service );
	free(domain);
	free(router_name);

	session->request_queue = NULL;
	session->remote_id = strdup(target_buf);
	session->orig_remote_id = strdup(session->remote_id);
	session->remote_service = strdup(remote_service);

	#ifdef ASSUME_STATELESS
	session->stateless = 1;
	debug_handler("session is stateless");
	#else
	session->stateless = 0;
	debug_handler("session is NOT stateless");
	#endif

	/* build a chunky, random session id */
	char id[256];
	memset(id,0,256);

	sprintf(id, "%lf.%d%d", get_timestamp_millis(), (int)time(NULL), getpid());
	session->session_id = strdup(id);
	debug_handler( "Building a new client session with id [%s] [%s]", 
			session->remote_service, session->session_id );

	session->thread_trace = 0;
	session->state = OSRF_SESSION_DISCONNECTED;
	session->type = OSRF_SESSION_CLIENT;
	session->next = NULL;
	_osrf_app_session_push_session( session );
	return session;
}

osrf_app_session* osrf_app_server_session_init( 
		char* session_id, char* our_app, char* remote_service, char* remote_id ) {

	osrf_app_session* session = osrf_app_session_find_session( session_id );
	if(session)
		return session;


	session = safe_malloc(sizeof(osrf_app_session));	

	session->transport_handle = osrf_system_get_transport_client();
	if( session->transport_handle == NULL ) {
		warning_handler("No transport client for service '%s'", our_app );
		return NULL;
	}
	session->request_queue = NULL;
	session->remote_id = strdup(remote_id);
	session->orig_remote_id = strdup(remote_id);
	session->session_id = strdup(session_id);
	session->remote_service = strdup(remote_service);

	#ifdef ASSUME_STATELESS
	session->stateless = 1;
	#else
	session->stateless = 0;
	#endif

	debug_handler( "Building a new server session [%s] with id [%s]", 
			session->remote_service,  session_id );

	session->thread_trace = 0;
	session->state = OSRF_SESSION_DISCONNECTED;
	session->type = OSRF_SESSION_CLIENT;
	session->next = NULL;

	_osrf_app_session_push_session( session );
	return session;

}



/** frees memory held by a session */
void _osrf_app_session_free( osrf_app_session* session ){
	if(session==NULL)
		return;
	
	free(session->remote_id);
	free(session->orig_remote_id);
	free(session->session_id);
	free(session->remote_service);
	free(session);
}

int osrf_app_session_make_req( 
		osrf_app_session* session, object* params, 
		char* method_name, int protocol, string_array* param_strings ) {
	if(session == NULL) return -1;

	osrf_message* req_msg = osrf_message_init( REQUEST, ++(session->thread_trace), protocol );
	osrf_message_set_method(req_msg, method_name);
	if(params) {
		osrf_message_set_params(req_msg, params);

	} else {

		if(param_strings) {
			int i;
			for(i = 0; i!= param_strings->size ; i++ ) {
				osrf_message_add_param(req_msg,
					string_array_get_string(param_strings,i));
			}
		}
	}

	osrf_app_request* req = _osrf_app_request_init( session, req_msg );
	if(!_osrf_app_session_send( session, req_msg ) ) {
		warning_handler( "Error sending request message [%d]", session->thread_trace );
		return -1;
	}

	_osrf_app_session_push_request( session, req );
	return req->request_id;
}



/** Adds an app_request to the request set */
void _osrf_app_session_push_request( osrf_app_session* session, osrf_app_request* req ){
	if(session == NULL || req == NULL)
		return;

	debug_handler( "Pushing [%d] onto requeust queue for session [%s] [%s]",
			req->request_id, session->remote_service, session->session_id );

	if(session->request_queue == NULL) 
		session->request_queue = req;
	else {
		osrf_app_request* req2 = session->request_queue->next;
		session->request_queue = req;
		req->next = req2;
	}
}



/** Removes an app_request from this session request set */
void _osrf_app_session_remove_request( osrf_app_session* session, osrf_app_request* req ){
	if(session == NULL || req == NULL)
		return;

	if(session->request_queue == NULL)
		return;

	debug_handler("Removing request [%d] from session [%s] [%s]",
			req->request_id, session->remote_service, session->session_id );

	osrf_app_request* first = session->request_queue;
	if(first->request_id == req->request_id) {
		session->request_queue = first->next;
		return;
		/*
		if(first->next == NULL) { 
			session->request_queue = NULL;
		} else {
			osrf_app_request* tmp = first->next;
			session->request_queue = tmp;
		}
		*/
	}

	osrf_app_request* lead = first->next;

	while( lead != NULL ) {
		if(lead->request_id == req->request_id) {
			first->next = lead->next;
			return;
		}
		first = lead;
		lead = lead->next;
	}
}


void osrf_app_session_set_complete( osrf_app_session* session, int request_id ) {
	if(session == NULL)
		return;

	osrf_app_request* req = _osrf_app_session_get_request( session, request_id );
	if(req) req->complete = 1;
}

int osrf_app_session_request_complete( osrf_app_session* session, int request_id ) {
	if(session == NULL)
		return 0;
	osrf_app_request* req = _osrf_app_session_get_request( session, request_id );
	if(req)
		return req->complete;
	return 0;
}

/** Returns the app_request with the given request_id (request_id) */
osrf_app_request* _osrf_app_session_get_request( 
		osrf_app_session* session, int request_id ){
	if(session == NULL)
		return NULL;

	debug_handler( "App Session searching for request [%d] in request queue",request_id );
	osrf_app_request* req = session->request_queue;
	while( req != NULL ) {
		if(req->request_id == request_id)
			return req;
		req = req->next;
	}
	return NULL;
}


/** Resets the remote connection id to that of the original*/
void osrf_app_session_reset_remote( osrf_app_session* session ){
	if( session==NULL )
		return;

	free(session->remote_id);
	debug_handler( "App Session [%s] [%s] resetting remote id to %s",
			session->remote_service, session->session_id, session->orig_remote_id );

	session->remote_id = strdup(session->orig_remote_id);
}

void osrf_app_session_set_remote( osrf_app_session* session, char* remote_id ) {
	if(session == NULL)
		return;
	if( session->remote_id )
		free(session->remote_id );
	session->remote_id = strdup( remote_id );
}

/** pushes the given message into the result list of the app_request
  with the given request_id */
int osrf_app_session_push_queue( 
		osrf_app_session* session, osrf_message* msg ){

	if(session == NULL || msg == NULL)
		return 0;

	debug_handler( "AppSession pushing result for [%d] onto request payload queue",
			msg->thread_trace );

	osrf_app_request* req = session->request_queue;

	if(req == NULL) {
		warning_handler( "app_session has no app_requests in its queue yet we have a result for [%d]", msg->thread_trace );
		return 0;
	}

	while( req != NULL ) {
		if(req->request_id == msg->thread_trace) {
			debug_handler( "Found app_request for tt [%d]", msg->thread_trace );
			_osrf_app_request_push_queue( req, msg );
			return 1;
		}
		req = req->next;
	} 

	return 0;
	
}

/** Attempts to connect to the remote service */
int osrf_app_session_connect(osrf_app_session* session){
	
	if(session == NULL)
		return 0;

	if(session->state == OSRF_SESSION_CONNECTED) {
		debug_handler("Already Connected, returning");
		return 1;
	}

	int timeout = 5; /* XXX CONFIG VALUE */

	debug_handler( "AppSession connecting to %s", session->remote_id );

	/* defaulting to protocol 1 for now */
	osrf_message* con_msg = osrf_message_init( CONNECT, session->thread_trace, 1 );
	osrf_app_session_reset_remote( session );
	session->state = OSRF_SESSION_CONNECTING;
	int ret = _osrf_app_session_send( session, con_msg );
	osrf_message_free(con_msg);
	if(!ret)	return 0;

	time_t start = time(NULL);	
	time_t remaining = (time_t) timeout;

	while( session->state != OSRF_SESSION_CONNECTED && remaining >= 0 ) {
		osrf_app_session_queue_wait( session, remaining );
		remaining -= (int) (time(NULL) - start);
	}

	if(session->state == OSRF_SESSION_CONNECTED)
		debug_handler(" * Connected Successfully");

	if(session->state != OSRF_SESSION_CONNECTED)
		return 0;

	return 1;
}



/** Disconnects from the remote service */
int osrf_app_session_disconnect( osrf_app_session* session){
	if(session == NULL)
		return 1;

	if(session->state == OSRF_SESSION_DISCONNECTED)
		return 1;

	if(session->stateless && session->state != OSRF_SESSION_CONNECTED) {
		debug_handler(
				"Exiting disconnect on stateless session %s", 
				session->session_id);
		return 1;
	}

	debug_handler( "AppSession disconnecting from %s", session->remote_id );

	osrf_message* dis_msg = osrf_message_init( DISCONNECT, session->thread_trace, 1 );
	session->state = OSRF_SESSION_DISCONNECTED;
	_osrf_app_session_send( session, dis_msg );

	osrf_message_free( dis_msg );
	osrf_app_session_reset_remote( session );
	return 1;
}

int osrf_app_session_request_resend( osrf_app_session* session, int req_id ) {
	debug_handler("In reqeust resend searching for resend-able messages");
	osrf_app_request* req = _osrf_app_session_get_request( session, req_id );
	return _osrf_app_request_resend( req );
}

/** Send the given message */
int _osrf_app_session_send( osrf_app_session* session, osrf_message* msg ){
	if(session == NULL) return 0;
	int ret_val= 0;

	osrf_app_session_queue_wait( session, 0 );
	debug_handler( "AppSession sending type %d, and thread_trace %d",
			msg->m_type, msg->thread_trace );

	if(session->stateless) {
		osrf_app_session_reset_remote(session);

	} else {

		if( (msg->m_type != CONNECT) && (msg->m_type != DISCONNECT) &&
				(session->state != OSRF_SESSION_CONNECTED) ) {
			if(!osrf_app_session_connect( session )) 
				return 0;
		}
	}

	//char* xml =  osrf_message_to_xml(msg);
	char* string =  osrf_message_serialize(msg);

	debug_handler("[%s] [%s] Remote Id: %s", 
			session->remote_service, session->session_id, session->remote_id );

	transport_message* t_msg = message_init( 
			string, "", session->session_id, session->remote_id, NULL );

	debug_handler("Session [%s] [%s]  sending to %s \nXML:\n%s", 
			session->remote_service, session->session_id, t_msg->recipient, string );
	ret_val = client_send_message( session->transport_handle, t_msg );
	free(string);
	message_free( t_msg );

	return ret_val; 
}

/**  Waits up to 'timeout' seconds for some data to arrive.
  * Any data that arrives will be processed according to its
  * payload and message type.  This method will return after
  * any data has arrived.
  */
int osrf_app_session_queue_wait( osrf_app_session* session, int timeout ){
	if(session == NULL) return 0;
	int ret_val = 0;
	debug_handler( "AppSession in queue_wait with timeout %d", timeout );
	ret_val = osrf_stack_process(session->transport_handle, timeout );
	return ret_val;
}

/** Disconnects (if client) and removes the given session from the global session cache 
  * ! This free's all attached app_requests ! 
  */
void osrf_app_session_destroy ( osrf_app_session* session ){
	if(session == NULL) return;

	debug_handler( "AppSession [%s] [%s] destroying self and deleting requests", 
			session->remote_service, session->session_id );
	if(session->type == OSRF_SESSION_CLIENT 
			&& session->state != OSRF_SESSION_DISCONNECTED ) { /* disconnect if we're a client */
		osrf_message* dis_msg = osrf_message_init( DISCONNECT, session->thread_trace, 1 );
		_osrf_app_session_send( session, dis_msg ); 
		osrf_message_free(dis_msg);
	}
	//session->state = OSRF_SESSION_DISCONNECTED;
	_osrf_app_session_remove_session(session->session_id);
	debug_handler("AppSession [%s] [%s] removed from cache", 
			session->remote_service, session->session_id );

	osrf_app_request* req;
	while( session->request_queue != NULL ) {
		req = session->request_queue->next;
		_osrf_app_request_free( session->request_queue );
		session->request_queue = req;
	}

	_osrf_app_session_free( session );
}

osrf_message* osrf_app_session_request_recv( 
		osrf_app_session* session, int req_id, int timeout ) {
	if(req_id < 0 || session == NULL)
		return NULL;
	debug_handler("somebody callled recv");
	osrf_app_request* req = _osrf_app_session_get_request( session, req_id );
	return _osrf_app_request_recv( req, timeout );
}

