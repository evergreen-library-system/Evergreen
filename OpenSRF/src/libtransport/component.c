#include "transport_client.h"
#include "signal.h"


/*
void print_stuff(void* blah, char* data) {
	fprintf(stderr, "Received from socket: %s\n", data);
}
*/

/* connects and registers with the router */
int main( int argc, char** argv ) {



	if( argc < 5 ) {
		osrfLogError(OSRF_LOG_MARK,  "Usage: %s <server> <port> <name> <secret>", argv[0] );
		return -1;
	}

	int port = atoi(argv[2]);
	transport_client* client = client_init( argv[1], port, 1 );

	// try to connect, allow 15 second connect timeout 
	if( client_connect( client, argv[3], argv[4], "", 15, 1 ) ) 
		osrfLogInfo(OSRF_LOG_MARK, "Connected...\n");
	 else  {
		osrfLogError(OSRF_LOG_MARK,  "NOT Connected...\n" ); 
		return -1;
	 }
	
	transport_message* recv;
	while( (recv=client_recv( client, -1)) ) {
		if( recv->is_error )
			fprintf( stderr, "\nReceived Error\t: ------------------\nFrom:\t\t"
				"%s\nRouterFrom:\t%s\nBody:\t\t%s\nType %s\nCode %d\n=> ", 
				recv->sender, recv->router_from, recv->body, recv->error_type, recv->error_code );
		else
			fprintf( stderr, "\nReceived\t: ------------------\nFrom:\t\t"
				"%s\nRouterFrom:\t%s\nBody:\t\t%s\n=> ", recv->sender, recv->router_from, recv->body );
		transport_message* send = message_init( "Hello...", "", "123454321", recv->sender, argv[3] );
		client_send_message( client, send );
		message_free( recv );
		message_free( send );
	}
	return 0;

}




