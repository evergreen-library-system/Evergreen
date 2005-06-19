#include "generic_utils.h"

#include <stdio.h>
#include <stdlib.h>
#include <sys/types.h>
#include <errno.h>

//---------------------------------------------------------------
// WIN32
//---------------------------------------------------------------
#ifdef WIN32
#include <Windows.h>
#include <Winsock.h>
#else

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
#endif

#ifndef TRANSPORT_SOCKET_H
#define TRANSPORT_SOCKET_H

/* how many characters we read from the socket at a time */
#ifdef _ROUTER
#define BUFSIZE 412
#else
#define BUFSIZE 4096
#endif

/* we maintain the socket information */
struct transport_socket_struct {
	/* for a client, sock_fd is THE socket connection.  For a server,
		it's the socket we listen on */
	int	sock_fd;
	int	connected;
	char* server; /* remote server name or ip */
	int	port;
	void* user_data;

	/* user_data may be anything.  it's whatever you wish
		to see showing up in the callback in addition to
		the acutal character data*/
	void (*data_received_callback) (void * user_data, char*);
};
typedef struct transport_socket_struct transport_socket;

/* connects.  If is_server is true, we call tcp_server_connect */
int tcp_connect( transport_socket* obj );

int tcp_send( transport_socket* obj, const char* data );

int tcp_disconnect( transport_socket* obj );

/* does both client and server waiting. 
	returns the socket_fd on success, 0 on error */
int tcp_wait( transport_socket* obj, int timeout );

int tcp_connected(transport_socket* obj);



#endif
