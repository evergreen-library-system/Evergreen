#include "utils.h"

#include <stdio.h>
#include <stdlib.h>
#include <sys/types.h>
#include <errno.h>

#include "utils.h"
#include "logging.h"

//---------------------------------------------------------------
// Unix headers
//---------------------------------------------------------------
#include <unistd.h>
#include <sys/time.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <sys/socket.h>
#include <arpa/inet.h>
#include <netdb.h>
#include <netinet/in.h>
#include <sys/un.h>

#include <signal.h>

#ifndef SOCKET_BUNDLE_H
#define SOCKET_BUNDLE_H


#define SERVER_SOCKET			1
#define CLIENT_SOCKET			2

#define INET 10 
#define UNIX 11 

/* buffer used to read from the sockets */
#define BUFSIZE 1024 


/* models a single socket connection */
struct socket_node_struct {
	int endpoint;		/* SERVER_SOCKET or CLIENT_SOCKET */
	int addr_type;		/* INET or UNIX */
	int sock_fd;
	int parent_id;		/* if we're a new client for a server socket, 
								this points to the server socket we spawned from */
	struct socket_node_struct* next;
};
typedef struct socket_node_struct socket_node;


/* Maintains the socket set */
struct socket_manager_struct {
	/* callback for passing up any received data.  sock_fd is the socket
		that read the data.  parent_id (if > 0) is the socket id of the 
		server that this socket spawned from (i.e. it's a new client connection) */
	void (*data_received) 
		(void* blob, struct socket_manager_struct*, 
		 int sock_fd, char* data, int parent_id);

	void (*on_socket_closed) (void* blob, int sock_fd);

	socket_node* socket;
	void* blob;
};
typedef struct socket_manager_struct socket_manager;

void socket_manager_free(socket_manager* mgr);

/* creates a new server socket node and adds it to the socket set.
	returns socket id on success.  -1 on failure.
	socket_type is one of INET or UNIX  */
int socket_open_tcp_server(socket_manager*, int port);

int socket_open_unix_server(socket_manager* mgr, char* path);

/* creates a client socket and adds it to the socket set.
	returns 0 on success.  -1 on failure.
	socket_type is one of INET or UNIX  
	port is the INET port number
	sock_path is the UNIX socket file
 */
int socket_open_client(socket_manager*, 
		int socket_type, int port, char* sock_path, char* dest_addr);

/* returns the socket_node with the given sock_fd */
socket_node* socket_find_node(socket_manager*, int sock_fd);

/* removes the node with the given sock_fd from the list and frees it */
void socket_remove_node(socket_manager*, int sock_fd);


/* sends the given data to the given socket. returns 0 on success, -1 otherwise */
int socket_send(int sock_fd, const char* data);

/* disconnects the node with the given sock_fd and removes
	it from the socket set */
void socket_disconnect(socket_manager*, int sock_fd);

/* allocates and inserts a new socket node into the nodeset.
	if parent_id is positive and non-zero, it will be set */
socket_node*  _socket_add_node(socket_manager* mgr, 
		int endpoint, int addr_type, int sock_fd, int parent_id );

int socket_wait(socket_manager* mgr, int timeout, int sock_fd);

/* waits on all sockets for incoming data.  
	timeout == -1	| block indefinitely
	timeout == 0	| don't block, just read any available data off all sockets
	timeout == x	| block for at most x seconds */
int socket_wait_all(socket_manager* mgr, int timeout);

/* iterates over the sockets in the set and handles active sockets.
	new sockets connecting to server sockets cause the creation
	of a new socket node.
	Any new data read is is passed off to the data_received callback
	as it arrives */
int _socket_route_data(socket_manager* mgr, int num_active, fd_set* read_set);

/* utility function for displaying the currently attached sockets */
void _socket_print_list(socket_manager* mgr);

int socket_connected(int sock_fd);


int _socket_handle_new_client(socket_manager* mgr, socket_node* node);
int _socket_handle_client_data(socket_manager* mgr, socket_node* node);


#endif
