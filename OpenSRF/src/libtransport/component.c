#include "opensrf/transport_client.h"
#include "signal.h"


/* connects and registers with the router */
int main( int argc, char** argv ) {

	if( argc < 5 ) {
		fatal_handler( "Usage: %s <server> <port> <name> <secret>", argv[0] );
	}

	int port = atoi(argv[2]);
	transport_client* client = client_init( argv[1], port, 1 );

	// try to connect, allow 15 second connect timeout 
	if( client_connect( client, argv[3], argv[4], "", 15 ) ) 
		info_handler("Connected...\n");
	 else  
		fatal_handler( "NOT Connected...\n" ); 
	
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




