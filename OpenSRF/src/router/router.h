#include "opensrf/transport_client.h"
#include "opensrf/transport_message.h"
#include "opensrf/osrf_message.h"

#include "opensrf/utils.h"
#include "opensrf/logging.h"
#include "opensrf/osrfConfig.h"

#include <time.h>
#include <sys/select.h>

#ifndef ROUTER_H
#define ROUTER_H

#define ROUTER_MAX_TRUSTED 256

// ----------------------------------------------------------------------
// Jabber router_registrar/load balancer.  There is a top level linked list of 
// server_class_nodes.  A server class represents the a cluster of Jabber
// clients that define a single logical routing endpoint.  Each of these 
// server_class_nodes maintains a list of connected server_nodes, which
// represents the pool of connected server endpoints.  A request 
// directed at a particular class is routed to the next available
// server endpoint.
//
// ----------------------------------------------------------------------


// ----------------------------------------------------------------------
// Defines an element in a server list.  The server list is a circular
// doubly linked list.  User is responsible for freeing a server_node with 
// server_node_free()
// ----------------------------------------------------------------------
struct server_node_struct {

	struct server_node_struct* next;
	struct server_node_struct* prev;

	time_t la_time;	/* last time we sent a message to a server */
	time_t reg_time;	/* time we originally registered */
	time_t upd_time;	/* last re-register time */
	int available;		/* true if we may be used */

	int serve_count; /* how many messages we've sent */

	/* jabber remote id  for this server node*/
	char* remote_id;

	/* we cache the last sent message in case our remote 
		endpoint has gone away.  If it has, the next server
		node in the list will re-send our last message */
	transport_message* last_sent;

};
typedef struct server_node_struct server_node;


// ----------------------------------------------------------------------
// Models a basic jabber connection structure.  Any component that 
// connects to jabber will have one of these.
// ----------------------------------------------------------------------
struct jabber_connect_struct {

	char* server;
	int port;
	char* username;
	char* password;
	char* resource;
	char* unixpath;
	int connect_timeout;

	transport_client* t_client;
};
typedef struct jabber_connect_struct jabber_connect;



// ----------------------------------------------------------------------
// Defines an element in the list of server classes.  User is 
// responsible for freeing a server_class_node with 
// server_class_node_free().
// The server_node_list is a doubly (not circular) linked list
// ----------------------------------------------------------------------
struct server_class_node_struct {

	/* the name of our class.  This will be used as the jabber
	 resource when we create a class level connection*/
	char* server_class;

	/* the current node in the ring of available server nodes */
	server_node* current_server_node;

	/* next and prev class_node pointers */
	struct server_class_node_struct* next;
	struct server_class_node_struct* prev;

	/* our jabber connection struct */
	jabber_connect* jabber;

};
typedef struct server_class_node_struct server_class_node;


// ----------------------------------------------------------------------
// Top level router_registrar object.  Maintains the list of 
// server_class_nodes and the top level router jabber connection.
// ----------------------------------------------------------------------
struct transport_router_registrar_struct {

	/* the list of server class nodes */
	server_class_node* server_class_list;

	/* if we don't hear from the client in this amount of time
		we consider them dead... */ 
	/* not currently used */
	int client_timeout; /* seconds */

	/* our top level connection to the jabber server */
	jabber_connect* jabber; 

	/* true if we connect to jabber as a jabber component */
	int component;

	osrfStringArray* trusted_servers;
	osrfStringArray* trusted_clients;

	//char** trusted_servers;
	//char** trusted_clients;


};
typedef struct transport_router_registrar_struct transport_router_registrar;


// ----------------------------------------------------------------------
// Returns an allocated transport_router_registrar.  The user is responsible for
// freeing the allocated memory with router_registrar_free()
// client_timeout is unused at this time.
// connect_timeout is how long we will wait for a failed jabber connect
// attempt for the top level connection.
// ----------------------------------------------------------------------
transport_router_registrar* router_registrar_init( char* server, 
		int port, char* unixpath, char* username, char* password, char* resource, 
		int client_timeout, int connect_timeout, int component );

// ----------------------------------------------------------------------
// Connects the top level router_registrar object to the Jabber server.
// ----------------------------------------------------------------------
int router_registrar_connect( transport_router_registrar* router );

// ----------------------------------------------------------------------
// Connects the given jabber_connect object to the Jabber server
// ----------------------------------------------------------------------
int j_connect( jabber_connect* jabber );


// ----------------------------------------------------------------------
// Builds and initializes a jabber_connect object. User is responsible
// for freeing the memory with jabber_connect_free();
// ----------------------------------------------------------------------
jabber_connect* jabber_connect_init( char* server, 
		int port, char* unixpath, char* username, char* password, 
		char* resource, int connect_timeout, int component );

// ----------------------------------------------------------------------
// Allocates and initializes a server class instance.  This will be
// called when a new class message arrives.  It will connect to Jabber
// as router_registrar->username@router_registrar->server/new_class
// ----------------------------------------------------------------------
server_class_node* init_server_class( 
		transport_router_registrar* router_registrar, char* remote_id, char* server_class ); 

// ----------------------------------------------------------------------
// Allocates and initializes a server_node object.  The object must
// be freed with server_node_free().  
// remote_id is the full jabber login for the remote server connection
// I.e. where we send messages when we want to send them to this 
// server.
// ----------------------------------------------------------------------
server_node* init_server_node(  char* remote_id );


// ----------------------------------------------------------------------
// Routes messages sent to the provided server_class_node's class
// ----------------------------------------------------------------------
int  server_class_handle_msg( transport_router_registrar* router, 
		server_class_node* s_node, transport_message* msg );

// ----------------------------------------------------------------------
// Determines what to do with an inbound register/unregister message.
// ----------------------------------------------------------------------
int router_registrar_handle_msg( transport_router_registrar*, transport_message* msg );

// ----------------------------------------------------------------------
// Deallocates the memory occupied by the given server_node
// ----------------------------------------------------------------------
int server_node_free( server_node* node );

// ----------------------------------------------------------------------
// Deallocates the memory used by the given server_class_node.  This
// will also free any attached server_node's.
// ----------------------------------------------------------------------
int server_class_node_free( server_class_node* node );

// ----------------------------------------------------------------------
// Deallocates the memory used by a server_node
// ----------------------------------------------------------------------
int server_node_free( server_node* node );


// ----------------------------------------------------------------------
// Deallocates a jabber_connect node
// ----------------------------------------------------------------------
int jabber_connect_free( jabber_connect* jabber );

// ----------------------------------------------------------------------
// Deallocates the memory used by the router_registrar.  This will also call
// server_class_node_free on any attached server_class_nodes.
// ----------------------------------------------------------------------
int router_registrar_free( transport_router_registrar* router_registrar );


// ----------------------------------------------------------------------
//  Returns the server_node with the given Jabber remote_id
// ----------------------------------------------------------------------
server_node * find_server_node ( server_class_node * class, const char * remote_id );


// ----------------------------------------------------------------------
// Returns the server_class_node object with the given class_name
// ----------------------------------------------------------------------
server_class_node * find_server_class ( transport_router_registrar * router, const char * class_id );

// ----------------------------------------------------------------------
// Removes a server class from the top level router_registrar
// ----------------------------------------------------------------------
int unregister_server_node( server_class_node* active_class_node, char* remote_id );

int fill_fd_set( transport_router_registrar* router, fd_set* set );

void listen_loop( transport_router_registrar* router );


int router_return_server_info( transport_router_registrar* router, transport_message* msg );

int remove_server_class( transport_router_registrar* router, server_class_node* class );



int router_registrar_handle_app_request( transport_router_registrar*, transport_message* msg );

osrf_message** router_registrar_process_app_request( 
		transport_router_registrar* , osrf_message* omsg, int* num_responses );


// ----------------------------------------------------------------------
// Adds a handler for the SIGUSR1 that we send to wake all the 
// listening threads.
// ----------------------------------------------------------------------
//void sig_handler( int sig );

#endif
