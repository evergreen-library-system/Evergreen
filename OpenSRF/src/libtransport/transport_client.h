#include "transport_session.h"
#include <time.h>

#ifndef TRANSPORT_CLIENT_H
#define TRANSPORT_CLIENT_H

#define MESSAGE_LIST_HEAD 1
#define MESSAGE_LIST_ITEM 2


// ---------------------------------------------------------------------------
// Represents a node in a linked list.  The node holds a pointer to the next
// node (which is null unless set), a pointer to a transport_message, and
// and a type variable (which is not really curently necessary).
// ---------------------------------------------------------------------------
struct message_list_struct {
	struct message_list_struct* next;
	transport_message* message;
	int type;
};

typedef struct message_list_struct transport_message_list;
typedef struct message_list_struct transport_message_node;

// ---------------------------------------------------------------------------
// Our client struct.  We manage a list of messages and a controlling session
// ---------------------------------------------------------------------------
struct transport_client_struct {
	transport_message_list* m_list;
	transport_session* session;
};
typedef struct transport_client_struct transport_client;

// ---------------------------------------------------------------------------
// Allocates and initializes and transport_client.  This does no connecting
// The user must call client_free(client) when finished with the allocated
// object.
// ---------------------------------------------------------------------------
transport_client* client_init( char* server, int port, int component );

// ---------------------------------------------------------------------------
// Connects to the Jabber server with the provided information. Returns 1 on
// success, 0 otherwise.
// ---------------------------------------------------------------------------
int client_connect( transport_client* client, 
		char* username, char* password, char* resource, 
		int connect_timeout, enum TRANSPORT_AUTH_TYPE auth_type );

int client_disconnect( transport_client* client );

// ---------------------------------------------------------------------------
// De-allocates memory associated with a transport_client object.  Users
// must use this method when finished with a client object.
// ---------------------------------------------------------------------------
int client_free( transport_client* client );

// ---------------------------------------------------------------------------
//  Sends the given message.  The message must at least have the recipient
// field set.
// ---------------------------------------------------------------------------
int client_send_message( transport_client* client, transport_message* msg );

// ---------------------------------------------------------------------------
// Returns 1 if this client is currently connected to the server, 0 otherwise
// ---------------------------------------------------------------------------
int client_connected( transport_client* client );

// ---------------------------------------------------------------------------
// This is the message handler required by transport_session.  This handler
// takes all incoming messages and puts them into the back of a linked list
// of messages.  
// ---------------------------------------------------------------------------
void client_message_handler( void* client, transport_message* msg );

// ---------------------------------------------------------------------------
// If there are any message in the message list, the 'oldest' message is
// returned.  If not, this function will wait at most 'timeout' seconds 
// for a message to arrive.  Specifying -1 means that this function will not
// return unless a message arrives.
// ---------------------------------------------------------------------------
transport_message* client_recv( transport_client* client, int timeout );


#endif
