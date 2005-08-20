// ---------------------------------------------------------------------------------
// Manages the Jabber session.  Data is taken from the TCP object and pushed into
// a SAX push parser as it arrives.  When key Jabber documetn elements are met, 
// logic ensues.
// ---------------------------------------------------------------------------------
#include "transport_message.h"

#include "utils.h"
#include "logging.h"
#include "socket_bundle.h"

#include "sha.h"

#include <string.h>
#include <libxml/globals.h>
#include <libxml/xmlerror.h>
#include <libxml/parser.h>
#include <libxml/parserInternals.h> /* only for xmlNewInputFromFile() */
#include <libxml/tree.h>
#include <libxml/debugXML.h>
#include <libxml/xmlmemory.h>

#ifndef TRANSPORT_SESSION_H
#define TRANSPORT_SESSION_H

#define CONNECTING_1 1 /* just starting the connection to Jabber */
#define CONNECTING_2 2 /* First <stream> packet sent and <stream> packet received from server */

/* Note. these are growing buffers, so all that's necessary is a sane starting point */
#define JABBER_BODY_BUFSIZE		4096
#define JABBER_SUBJECT_BUFSIZE	64	
#define JABBER_THREAD_BUFSIZE		64	
#define JABBER_JID_BUFSIZE			64	
#define JABBER_STATUS_BUFSIZE		16 

// ---------------------------------------------------------------------------------
// Takes data from the socket handler and pushes it directly into the push parser
// ---------------------------------------------------------------------------------
//void grab_incoming( void * session, char* data );
void grab_incoming(void* blob, socket_manager* mgr, int sockid, char* data, int parent);

// ---------------------------------------------------------------------------------
// Callback for handling the startElement event.  Much of the jabber logic occurs
// in this and the characterHandler callbacks.
// Here we check for the various top level jabber elements: body, iq, etc.
// ---------------------------------------------------------------------------------
void startElementHandler( 
		void *session, const xmlChar *name, const xmlChar **atts);

// ---------------------------------------------------------------------------------
// Callback for handling the endElement event.  Updates the Jabber state machine
// to let us know the element is over.
// ---------------------------------------------------------------------------------
void endElementHandler( void *session, const xmlChar *name);

// ---------------------------------------------------------------------------------
// This is where we extract XML text content.  In particular, this is useful for
// extracting Jabber message bodies.
// ---------------------------------------------------------------------------------
void characterHandler(
		void *session, const xmlChar *ch, int len);

void  parseWarningHandler( void *session, const char* msg, ... );
void  parseErrorHandler( void *session, const char* msg, ... );

// ---------------------------------------------------------------------------------
// Tells the SAX parser which functions will be used as event callbacks
// ---------------------------------------------------------------------------------
static xmlSAXHandler SAXHandlerStruct = {
   NULL,							/* internalSubset */
   NULL,							/* isStandalone */
   NULL,							/* hasInternalSubset */
   NULL,							/* hasExternalSubset */
   NULL,							/* resolveEntity */
   NULL,							/* getEntity */
   NULL,							/* entityDecl */
   NULL,							/* notationDecl */
   NULL,							/* attributeDecl */
   NULL,							/* elementDecl */
   NULL,							/* unparsedEntityDecl */
   NULL,							/* setDocumentLocator */
   NULL,							/* startDocument */
   NULL,							/* endDocument */
	startElementHandler,		/* startElement */
	endElementHandler,		/* endElement */
   NULL,							/* reference */
	characterHandler,			/* characters */
   NULL,							/* ignorableWhitespace */
   NULL,							/* processingInstruction */
   NULL,							/* comment */
   parseWarningHandler,		/* xmlParserWarning */
   parseErrorHandler,		/* xmlParserError */
   NULL,							/* xmlParserFatalError : unused */
   NULL,							/* getParameterEntity */
   NULL,							/* cdataBlock; */
   NULL,							/* externalSubset; */
   1,
   NULL,
   NULL,							/* startElementNs */
   NULL,							/* endElementNs */
	NULL							/* xmlStructuredErrorFunc */
};

// ---------------------------------------------------------------------------------
// Our SAX handler pointer.
// ---------------------------------------------------------------------------------
static const xmlSAXHandlerPtr SAXHandler = &SAXHandlerStruct;

// ---------------------------------------------------------------------------------
// Jabber state machine.  This is how we know where we are in the Jabber
// conversation.
// ---------------------------------------------------------------------------------
struct jabber_state_machine_struct {
	int connected;
	int connecting;
	int in_message;
	int in_message_body;
	int in_thread;
	int in_subject;
	int in_error;
	int in_message_error;
	int in_iq;
	int in_presence;
	int in_status;
};
typedef struct jabber_state_machine_struct jabber_machine;


enum TRANSPORT_AUTH_TYPE { AUTH_PLAIN, AUTH_DIGEST };

// ---------------------------------------------------------------------------------
// Transport session.  This maintains all the various parts of a session
// ---------------------------------------------------------------------------------
struct transport_session_struct {

	/* our socket connection */
	//transport_socket* sock_obj;
	socket_manager* sock_mgr;

	/* our Jabber state machine */
	jabber_machine* state_machine;
	/* our SAX push parser context */
	xmlParserCtxtPtr parser_ctxt;

	/* our text buffers for holding text data */
	growing_buffer* body_buffer;
	growing_buffer* subject_buffer;
	growing_buffer* thread_buffer;
	growing_buffer* from_buffer;
	growing_buffer* recipient_buffer;
	growing_buffer* status_buffer;
	growing_buffer* message_error_type;
	growing_buffer* session_id;
	int message_error_code;

	/* for OILS extenstions */
	growing_buffer* router_to_buffer;
	growing_buffer* router_from_buffer;
	growing_buffer* router_class_buffer;
	growing_buffer* router_command_buffer;
	int router_broadcast;

	/* this can be anything.  It will show up in the 
		callbacks for your convenience. Otherwise, it's
		left untouched.  */
	void* user_data;

	char* server;
	char* unix_path;
	int	port;
	int sock_id;

	int component; /* true if we're a component */

	/* the Jabber message callback */
	void (*message_callback) ( void* user_data, transport_message* msg );
	//void (iq_callback) ( void* user_data, transport_iq_message* iq );
};
typedef struct transport_session_struct transport_session;


// ------------------------------------------------------------------
// Allocates and initializes the necessary transport session
// data structures.
// If port > 0, then this session uses  TCP connection.  Otherwise,
// if unix_path != NULL, it uses a UNIX domain socket.
// ------------------------------------------------------------------
transport_session* init_transport( char* server, int port, 
	char* unix_path, void* user_data, int component );

// ------------------------------------------------------------------
// Returns the value of the given XML attribute
// The xmlChar** construct is commonly returned from SAX event
// handlers.  Pass that in with the name of the attribute you want
// to retrieve.
// ------------------------------------------------------------------
char* get_xml_attr( const xmlChar** atts, char* attr_name );

// ------------------------------------------------------------------
// Waits  at most 'timeout' seconds  for data to arrive from the 
// TCP handler. A timeout of -1 means to wait indefinitely.
// ------------------------------------------------------------------
int session_wait( transport_session* session, int timeout );

// ---------------------------------------------------------------------------------
// Sends the given Jabber message
// ---------------------------------------------------------------------------------
int session_send_msg( transport_session* session, transport_message* msg );

// ---------------------------------------------------------------------------------
// Returns 1 if this session is connected to the jabber server. 0 otherwise
// ---------------------------------------------------------------------------------
int session_connected( transport_session* );

// ------------------------------------------------------------------
// Deallocates session memory
// ------------------------------------------------------------------
int session_free( transport_session* session );

// ------------------------------------------------------------------
// Connects to the Jabber server.  Waits at most connect_timeout
// seconds before failing
// ------------------------------------------------------------------
int session_connect( transport_session* session, 
		const char* username, const char* password, 
		const char* resource, int connect_timeout, 
		enum TRANSPORT_AUTH_TYPE auth_type );

int session_disconnect( transport_session* session );

int reset_session_buffers( transport_session* session );

#endif
