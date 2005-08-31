#include <string.h>
#include <libxml/globals.h>
#include <libxml/xmlerror.h>
#include <libxml/parser.h>
#include <libxml/tree.h>
#include <libxml/debugXML.h>
#include <libxml/xmlmemory.h>

#include "opensrf/utils.h"
#include "opensrf/logging.h"

#ifndef TRANSPORT_MESSAGE_H
#define TRANSPORT_MESSAGE_H



// ---------------------------------------------------------------------------------
// Jabber message object.
// ---------------------------------------------------------------------------------
struct transport_message_struct {
	char* body;
	char* subject;
	char* thread;
	char* recipient;
	char* sender;
	char* router_from;
	char* router_to;
	char* router_class;
	char* router_command;
	int is_error;
	char* error_type;
	int error_code;
	int broadcast;
	char* msg_xml; /* the entire message as XML complete with entity encoding */
};
typedef struct transport_message_struct transport_message;

// ---------------------------------------------------------------------------------
// Allocates and returns a transport_message.  All chars are safely re-allocated
// within this method.
// Returns NULL on error
// ---------------------------------------------------------------------------------
transport_message* message_init( char* body, char* subject, 
		char* thread, char* recipient, char* sender );

transport_message* new_message_from_xml( const char* msg_xml );


void message_set_router_info( transport_message* msg, char* router_from,
		char* router_to, char* router_class, char* router_command, int broadcast_enabled );

// ---------------------------------------------------------------------------------
// Formats the Jabber message as XML for encoding. 
// Returns NULL on error
// ---------------------------------------------------------------------------------
char* message_to_xml( const transport_message* msg );


// ---------------------------------------------------------------------------------
// Call this to create the encoded XML for sending on the wire.
// This is a seperate function so that encoding will not necessarily have
// to happen on all messages (i.e. typically only occurs outbound messages).
// ---------------------------------------------------------------------------------
int message_prepare_xml( transport_message* msg );

// ---------------------------------------------------------------------------------
// Deallocates the memory used by the transport_message
// Returns 0 on error
// ---------------------------------------------------------------------------------
int message_free( transport_message* msg );

// ---------------------------------------------------------------------------------
// Prepares the shared XML document
// ---------------------------------------------------------------------------------
//int message_init_xml();

// ---------------------------------------------------------------------------------
// Determines the username of a Jabber ID.  This expects a pre-allocated char 
// array for the return value.
// ---------------------------------------------------------------------------------
void jid_get_username( const char* jid, char buf[] );

// ---------------------------------------------------------------------------------
// Determines the resource of a Jabber ID.  This expects a pre-allocated char 
// array for the return value.
// ---------------------------------------------------------------------------------
void jid_get_resource( const char* jid, char buf[] );

/** Puts the domain portion of the given jid into the pre-allocated buffer */
void jid_get_domain( const char* jid, char buf[] );

void set_msg_error( transport_message*, char* error_type, int error_code);


#endif
