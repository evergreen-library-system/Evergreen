#include "opensrf/transport_socket.h"


/*
int main( char* argc, char** argv ) {

	transport_socket sock_obj;
	sock_obj.port = 5222;
	sock_obj.server = "10.0.0.4";
	sock_obj.data_received_callback = &print_stuff;

	printf("connecting...\n");
	if( (tcp_connect( &sock_obj )) < 0 ) {
		printf( "error connecting" );
	}

	printf("sending...\n");
	if( tcp_send( &sock_obj, "<stream>\n" ) < 0 ) {
		printf( "error sending" );
	}
	
	printf("waiting...\n");
	if( tcp_wait( &sock_obj, 15 ) < 0 ) {
		printf( "error receiving" );
	}

	printf("disconnecting...\n");
	tcp_disconnect( &sock_obj );

}
*/


// returns the socket fd, -1 on error
int tcp_connect( transport_socket* sock_obj ){

	if( sock_obj == NULL ) {
		fatal_handler( "connect(): null sock_obj" );
		return -1;
	}
	struct sockaddr_in remoteAddr, localAddr;
	struct hostent *hptr;
	int sock_fd;

	#ifdef WIN32
	WSADATA data;
	char bfr;
	if( WSAStartup(MAKEWORD(1,1), &data) ) {
		fatal_handler( "somethin's broke with windows socket startup" );
		return -1;
	}
	#endif



	// ------------------------------------------------------------------
	// Create the socket
	// ------------------------------------------------------------------
	if( (sock_fd = socket( AF_INET, SOCK_STREAM, 0 )) < 0 ) {
		fatal_handler( "tcp_connect(): Cannot create socket" );
		return -1;
	}

	// ------------------------------------------------------------------
	// Get the hostname
	// ------------------------------------------------------------------
	if( (hptr = gethostbyname( sock_obj->server ) ) == NULL ) {
		fatal_handler( "tcp_connect(): Unknown Host" );
		return -1;
	}

	// ------------------------------------------------------------------
	// Construct server info struct
	// ------------------------------------------------------------------
	memset( &remoteAddr, 0, sizeof(remoteAddr));
	remoteAddr.sin_family = AF_INET;
	remoteAddr.sin_port = htons( sock_obj->port );
	memcpy( (char*) &remoteAddr.sin_addr.s_addr,
			hptr->h_addr_list[0], hptr->h_length );

	// ------------------------------------------------------------------
	// Construct local info struct
	// ------------------------------------------------------------------
	memset( &localAddr, 0, sizeof( localAddr ) );
	localAddr.sin_family = AF_INET;
	localAddr.sin_addr.s_addr = htonl( INADDR_ANY );
	localAddr.sin_port = htons(0);

	// ------------------------------------------------------------------
	// Bind to a local port
	// ------------------------------------------------------------------
	if( bind( sock_fd, (struct sockaddr *) &localAddr, sizeof( localAddr ) ) < 0 ) {
		fatal_handler( "tcp_connect(): Cannot bind to local port" );
		return -1;
	}

	// ------------------------------------------------------------------
	// Connect to server
	// ------------------------------------------------------------------
	if( connect( sock_fd, (struct sockaddr*) &remoteAddr, sizeof( struct sockaddr_in ) ) < 0 ) {
		fatal_handler( "tcp_connect(): Cannot connect to server %s", sock_obj->server );
		return -1;
	}

	sock_obj->sock_fd = sock_fd;
	sock_obj->connected = 1;
	return sock_fd;

}


int tcp_send( transport_socket* sock_obj, const char* data ){

	if( sock_obj == NULL ) {
		fatal_handler( "tcp_send(): null sock_obj" );
		return 0;
	}

	//fprintf( stderr, "TCP Sending: \n%s\n", data );

	// ------------------------------------------------------------------
	// Send the data down the TCP pipe
	// ------------------------------------------------------------------
	debug_handler( "Sending Data At %f Seconds", get_timestamp_millis() );
	if( send( sock_obj->sock_fd, data, strlen(data), 0 ) < 0 ) {
		fatal_handler( "tcp_send(): Error sending data" );
		return 0;
	}
	return 1;
}


int tcp_disconnect( transport_socket* sock_obj ){

	if( sock_obj == NULL ) {
		fatal_handler( "tcp_disconnect(): null sock_obj" );
		return -1;
	}

	if( close( sock_obj->sock_fd ) == -1 ) {

		// ------------------------------------------------------------------
		// Not really worth throwing an exception for... should be logged.
		// ------------------------------------------------------------------
		warning_handler( "tcp_disconnect(): Error closing socket" );
		return -1;
	} 

	return 0;
}

// ------------------------------------------------------------------
// And now for the gory C socket code.
// Returns 0 on failure, 1 otherwise
// ------------------------------------------------------------------
int tcp_wait( transport_socket* sock_obj, int timeout ){

	if( sock_obj == NULL ) {
		fatal_handler( "tcp_wait(): null sock_obj" );
		return 0;
	}

	int n = 0; 
	int retval = 0;
	char buf[BUFSIZE];
	int sock_fd = sock_obj->sock_fd;


	fd_set read_set;

	FD_ZERO( &read_set );
	FD_SET( sock_fd, &read_set );

	// ------------------------------------------------------------------
	// Build the timeval struct
	// ------------------------------------------------------------------
	struct timeval tv;
	tv.tv_sec = timeout;
	tv.tv_usec = 0;

	if( timeout == -1 ) {  

		// ------------------------------------------------------------------
		// If timeout is -1, there is no timeout passed to the call to select
		// ------------------------------------------------------------------
		if( (retval = select( sock_fd + 1 , &read_set, NULL, NULL, NULL)) == -1 ) {
			warning_handler( "Call to select interrupted" );
			return 0;
		}

	} else if( timeout != 0 ) { /* timeout of 0 means don't block */

		if( (retval = select( sock_fd + 1 , &read_set, NULL, NULL, &tv)) == -1 ) {
			warning_handler( "Call to select interrupted" );
			return 0;
		}
	}

	memset( &buf, 0, BUFSIZE );

	if( set_fl( sock_fd, O_NONBLOCK ) < 0 ) 
		return 0;

#ifdef _ROUTER // just read one buffer full of data

	n = recv(sock_fd, buf, BUFSIZE-1, 0);
	sock_obj->data_received_callback( sock_obj->user_data, buf );
	if( n == 0 )
		n = -1;

#else // read everything we can

	debug_handler( "Leaving Socket Select At %f Seconds", get_timestamp_millis() );
	while( (n = recv(sock_fd, buf, BUFSIZE-1, 0) ) > 0 ) {
		debug_handler("SOCKET Read:  \n%s\n", buf);
		sock_obj->data_received_callback( sock_obj->user_data, buf );
		memset( &buf, 0, BUFSIZE );
	}

#endif

	if( clr_fl( sock_fd, O_NONBLOCK ) < 0 ) {
		return 0;
	}

	if( n < 0 ) { 
		if( errno != EAGAIN ) { 
			warning_handler( " * Error reading socket with errno %d", errno );
			return 0;
		}
	}

#ifdef _ROUTER
	return n;
#else
	return 1;
#endif

}

int set_fl( int fd, int flags ) {
	
	int val;

	if( (val = fcntl( fd, F_GETFL, 0) ) < 0 ) {
		fatal_handler("fcntl F_GETFL error");
		return -1;
	}

	val |= flags;

	if( fcntl( fd, F_SETFL, val ) < 0 ) {
		fatal_handler( "fcntl F_SETFL error" );
		return -1;
	}
	return 0;
}
	
int clr_fl( int fd, int flags ) {
	
	int val;

	if( (val = fcntl( fd, F_GETFL, 0) ) < 0 ) {
		fatal_handler("fcntl F_GETFL error" );
		return -1;
	}

	val &= ~flags;

	if( fcntl( fd, F_SETFL, val ) < 0 ) {
		fatal_handler( "fcntl F_SETFL error" );
		return -1;
	}
	return 0;
}
	

/*
int tcp_connected( transport_socket* obj ) {

	int ret;
	if( ! obj->sock_fd ) { return 0; }

	ret = read( obj->sock_fd  , NULL,0 );
	if( ret <= 0 ) {
		return 0;
	}
	return 1;
}
*/

