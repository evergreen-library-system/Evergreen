#include "opensrf/transport_client.h"

/**
  * Simple jabber client
  */



/* connects and registers with the router */
int main( int argc, char** argv ) {

	if( argc < 5 ) {
		fatal_handler( "Usage: %s <username> <host> <resource> <recipient> \n", argv[0] );
		return 99;
	}

	transport_message* send;
	transport_client* client = client_init( argv[2], 5222 );

	// try to connect, allow 15 second connect timeout 
	if( client_connect( client, argv[1], "asdfjkjk", argv[3], 15 ) ) 
		info_handler("Connected...\n");
	 else  
		fatal_handler( "NOT Connected...\n" ); 
	
	if( fork() ) {

		fprintf(stderr, "Listener: %d\n", getpid() );	
		char buf[300];
		memset(buf, 0, 300);
		printf("=> ");

		while( fgets( buf, 299, stdin) ) {

			// remove newline
			buf[strlen(buf)-1] = '\0';

			if( strcmp(buf, "exit")==0) { 
				client_free( client );	
				break; 
			}

			send = message_init( buf, "", "123454321", argv[4], NULL );
			client_send_message( client, send );
			message_free( send );
			printf("\n=> ");
			memset(buf, 0, 300);
		}
		return 0;

	} else {

		fprintf(stderr, "Sender: %d\n", getpid() );	

		transport_message* recv;
		while( (recv=client_recv( client, -1)) ) {
			if( recv->is_error )
				fprintf( stderr, "\nReceived Error\t: ------------------\nFrom:\t\t"
					"%s\nRouterFrom:\t%s\nBody:\t\t%s\nType %s\nCode %d\n=> ", recv->sender, recv->router_from, recv->body, recv->error_type, recv->error_code );
			else
				fprintf( stderr, "\nReceived\t: ------------------\nFrom:\t\t"
					"%s\nRouterFrom:\t%s\nBody:\t\t%s\n=> ", recv->sender, recv->router_from, recv->body );

			message_free( recv );
		}

	}
	return 0;

}




