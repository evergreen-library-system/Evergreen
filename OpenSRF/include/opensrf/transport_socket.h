#include "opensrf/generic_utils.h"

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
	int sock_fd;
	int connected;
	char* server;
	int port;
	void * user_data;
	/* user_data may be anything.  it's whatever you wish
		to see showing up in the callback in addition to
		the acutal character data*/
	void (*data_received_callback) (void * user_data, char*);
};
typedef struct transport_socket_struct transport_socket;

int tcp_connect( transport_socket* obj );
int tcp_send( transport_socket* obj, const char* data );
int tcp_disconnect( transport_socket* obj );
int tcp_wait( transport_socket* obj, int timeout );
int tcp_connected( transport_socket* obj );

/* utility methods */
int set_fl( int fd, int flags );
int clr_fl( int fd, int flags );


#endif
