#include "libjson/json.h"
#include "opensrf/transport_client.h"
#include "opensrf/generic_utils.h"
#include "osrf_message.h"
#include "osrf_system.h"

#ifndef OSRF_APP_SESSION
#define OSRF_APP_SESSION


#define	DEF_RECV_TIMEOUT 6 /* receive timeout */
#define	DEF_QUEUE_SIZE	

enum OSRF_SESSION_STATE { OSRF_SESSION_CONNECTING, OSRF_SESSION_CONNECTED, OSRF_SESSION_DISCONNECTED };
enum OSRF_SESSION_TYPE { OSRF_SESSION_SERVER, OSRF_SESSION_CLIENT };

struct osrf_app_request_struct {
	/** Our controlling session */
	struct osrf_app_session_struct* session;

	/** our "id" */
	int request_id;
	/** True if we have received a 'request complete' message from our request */
	int complete;
	/** Our original request payload */
	osrf_message* payload; 
	/** List of responses to our request */
	osrf_message* result;

	/** So we can be listified */
	struct osrf_app_request_struct* next;
};
typedef struct osrf_app_request_struct osrf_app_request;

struct osrf_app_session_struct {

	/** Our messag passing object */
	transport_client* transport_handle;
	/** Cache of active app_request objects */
	osrf_app_request* request_queue;

	/** The original remote id of the remote service we're talking to */
	char* orig_remote_id;
	/** The current remote id of the remote service we're talking to */
	char* remote_id;

	/** Who we're talking to */
	char* remote_service;

	/** The current request thread_trace */
	int thread_trace;
	/** Our ID */
	char* session_id;

	/** The connect state */
	enum OSRF_SESSION_STATE state;

	/** SERVER or CLIENT */
	enum OSRF_SESSION_TYPE type;

	/** So we can be listified */
	struct osrf_app_session_struct* next;
};
typedef struct osrf_app_session_struct osrf_app_session;



// -------------------------------------------------------------------------- 
// PUBLIC API ***
// -------------------------------------------------------------------------- 

/** Allocates a initializes a new app_session */
osrf_app_session* osrf_app_client_session_init( char* remote_service );

/** Allocates and initializes a new server session.  The global session cache
  * is checked to see if this session already exists, if so, it's returned 
  */
osrf_app_session* osrf_app_server_session_init( 
		char* session_id, char* our_app, char* remote_service, char* remote_id );

/** returns a session from the global session hash */
osrf_app_session* osrf_app_session_find_session( char* session_id );

/** Builds a new app_request object with the given payload andn returns
  * the id of the request.  This id is then used to perform work on the
  * requeset.
  */
int osrf_app_session_make_request( 
		osrf_app_session* session, json* params, char* method_name, int protocol );

/** Sets the given request to complete state */
void osrf_app_session_set_complete( osrf_app_session* session, int request_id );

/** Returns true if the given request is complete */
int osrf_app_session_complete( osrf_app_session* session, int request_id );

/** Does a recv call on the given request */
osrf_message* osrf_app_session_request_recv( 
		osrf_app_session* session, int request_id, int timeout );

/** Removes the request from the request set and frees the reqest */
void osrf_app_session_request_finish( osrf_app_session* session, int request_id );

/** Resends the orginal request with the given request id */
int osrf_app_session_request_resend( osrf_app_session*, int request_id );

/** Resets the remote connection target to that of the original*/
void osrf_app_session_reset_remote( osrf_app_session* );

/** Sets the remote target to 'remote_id' */
void osrf_app_session_set_remote( osrf_app_session* session, char* remote_id );

/** pushes the given message into the result list of the app_request
  * whose request_id matches the messages thread_trace 
  */
int osrf_app_session_push_queue( osrf_app_session*, osrf_message* msg );

/** Attempts to connect to the remote service. Returns 1 on successful 
  * connection, 0 otherwise.
  */
int osrf_app_session_connect( osrf_app_session* );

/** Sends a disconnect message to the remote service.  No response is expected */
int osrf_app_session_disconnect( osrf_app_session* );

/**  Waits up to 'timeout' seconds for some data to arrive.
  * Any data that arrives will be processed according to its
  * payload and message type.  This method will return after
  * any data has arrived.
  */
int osrf_app_session_queue_wait( osrf_app_session*, int timeout );

/** Disconnects (if client), frees any attached app_reuqests, removes the session from the 
  * global session cache and frees the session.  Needless to say, only call this when the
  * session is completey done.
  */
void osrf_app_session_destroy ( osrf_app_session* );



// --------------------------------------------------------------------------
// --------------------------------------------------------------------------
// Request functions
// --------------------------------------------------------------------------

/** Allocations and initializes a new app_request object */
osrf_app_request* _osrf_app_request_init( osrf_app_session* session, osrf_message* msg );

/** Frees memory used by an app_request object */
void _osrf_app_request_free( osrf_app_request * req );

/** Pushes the given message onto the list of 'responses' to this request */
void _osrf_app_request_push_queue( osrf_app_request*, osrf_message* payload );

/** Checks the receive queue for messages.  If any are found, the first
  * is popped off and returned.  Otherwise, this method will wait at most timeout 
  * seconds for a message to appear in the receive queue.  Once it arrives it is returned.
  * If no messages arrive in the timeout provided, null is returned.
  */
osrf_message* _osrf_app_request_recv( osrf_app_request* req, int timeout );

/** Resend this requests original request message */
int _osrf_app_request_resend( osrf_app_request* req );


// --------------------------------------------------------------------------
// --------------------------------------------------------------------------
// Session functions 
// --------------------------------------------------------------------------

/** Returns the app_request with the given thread_trace (request_id) */
osrf_app_request* _osrf_app_session_get_request( osrf_app_session*, int thread_trace );

/** frees memory held by a session. Note: We delete all requests in the request list */
void _osrf_app_session_free( osrf_app_session* );

/** adds a session to the global session cache */
void _osrf_app_session_push_session( osrf_app_session* );

/** removes from global session cache */
void _osrf_app_session_remove_session( char* session_id );

/** Adds an app_request to the request set */
void _osrf_app_session_push_request( osrf_app_session*, osrf_app_request* req );

/** Removes an app_request from this session request set, freeing the request object */
void _osrf_app_session_remove_request( osrf_app_session*, osrf_app_request* req );

/** Send the given message */
int _osrf_app_session_send( osrf_app_session*, osrf_message* msg );

#endif
