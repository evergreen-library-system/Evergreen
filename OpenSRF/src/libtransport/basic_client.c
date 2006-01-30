#include "transport_client.h"
#include "signal.h"

pid_t pid;
void sig_int( int sig ) {
	fprintf(stderr, "Killing child %d\n", pid );
	kill( pid, SIGKILL );
}

/* connects and registers with the router */
int main( int argc, char** argv ) {

	if( argc < 5 ) {
		osrfLogError( OSRF_LOG_MARK, "Usage: %s <username> <host> <resource> <recipient> \n", argv[0] );
		return 99;
	}

	transport_message* send;
	transport_client* client = client_init( argv[2], 5222, 0 );

	// try to connect, allow 15 second connect timeout 
	if( client_connect( client, argv[1], "jkjkasdf", argv[3], 15, AUTH_DIGEST ) ) 
		osrfLogInfo(OSRF_LOG_MARK, "Connected...\n");
	 else { 
		osrfLogError( OSRF_LOG_MARK, "NOT Connected...\n" ); 
		return -1;
	 }
	
	if( (pid=fork()) ) { /* parent */

		signal(SIGINT, sig_int);
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
		fprintf(stderr, "Killing child %d\n", pid );
		kill( pid, SIGKILL );
		return 0;

	} else {

		fprintf(stderr, "Sender: %d\n", getpid() );	

		transport_message* recv;
		while( (recv=client_recv( client, -1)) ) {
			if( recv->is_error )
				fprintf( stderr, "\nReceived Error\t: ------------------\nFrom:\t\t"
					"%s\nRouterFrom:\t%s\nBody:\t\t%s\nType %s\nCode %d\n=> ", 
					recv->sender, recv->router_from, recv->body, recv->error_type, recv->error_code );
			else
				fprintf( stderr, "\nReceived\t: ------------------\nFrom:\t\t"
					"%s\nRouterFrom:\t%s\nBody:\t\t%s\n=> ", recv->sender, recv->router_from, recv->body );

			message_free( recv );
		}

	}
	return 0;

}




