#include "opensrf/transport_client.h"
#include "opensrf/generic_utils.h"
#include <time.h>

#define SRFSH_PORT 5222
#define COMMAND_BUFSIZE 12


char* prompt = "srfsh# ";
transport_client* client = NULL;

int parse_request( char* request );
int handle_router( char* words[] );
int handle_time( char* words[] );
int parse_error( char* words[] );
int router_query_servers( char* server );
int srfsh_client_connect();
void print_help();

int main( int argc, char* argv[] ) {


	if( argc < 4 ) 
		fatal_handler( "usage: %s <jabbersever> <username> <password>", argv[0] );
		
	char request[256];
	memset(request, 0, 256);
	printf(prompt);

	client = client_init( argv[1], SRFSH_PORT );
	if( ! client_connect( client, argv[2], argv[3], "srfsh", 5 ) ) {
		fprintf(stderr, "Unable to connect to jabber server '%s' as '%s'\n", argv[1], argv[2]);
		fprintf(stderr, "Most queries will be futile...\n" );
	}


	while( fgets( request, 255, stdin) ) {

		// remove newline
		request[strlen(request)-1] = '\0';

		if( !strcmp(request, "exit") || !strcmp(request,"quit")) { 
			client_disconnect( client );
			client_free( client );	
			break; 
		}


		if( !strcmp(request, "help") || !strcmp(request,"?")) 
			print_help();
		else 
			parse_request( request );

		printf(prompt);
		memset(request, 0, 300);
	}

	fprintf(stderr, "Exiting...\n[Ignore Segfault]\n");
	return 0;
}


int parse_error( char* words[] ) {

	if( ! words )
		return 0;

	int i = 0;
	char* current;
	char buffer[256];
	memset(buffer, 0, 256);
	while( (current=words[i++]) ) {
		strcat(buffer, current);
		strcat(buffer, " ");
	}
	if( ! buffer || strlen(buffer) < 1 ) 
		printf("\n");

	fprintf( stderr, "Command Incomplete or Not Recognized: %s\n", buffer );
	return 0;

}


int parse_request( char* request ) {

	if( request == NULL )
		return 0;

	int ret_val = 0;
	int i = 0;
	char* words[COMMAND_BUFSIZE]; 
	memset(words,0,COMMAND_BUFSIZE);

	char* cur_tok = strtok( request, " " );

	if( cur_tok == NULL )
		return 0;

	while(cur_tok != NULL) {
		words[i++] = cur_tok;
		cur_tok = strtok( NULL, " " );
	}

	// not sure why (strtok?), but this is necessary
	memset( words + i, 0, COMMAND_BUFSIZE - i );

	/* pass off to the top level command */
	if( !strcmp(words[0],"router") ) 
		ret_val = handle_router( words );

	if( !strcmp(words[0],"time") ) 
		ret_val = handle_time( words );

	if(!ret_val)
		return parse_error( words );

	return 1;

}


int handle_router( char* words[] ) {

	if(!client)
		return 1;

	int i;

	if( words[1] ) { 
		if( !strcmp(words[1],"query") ) {
			
			if( words[2] && !strcmp(words[2],"servers") ) {
				for(i=3; i < COMMAND_BUFSIZE - 3 && words[i]; i++ ) {	
					router_query_servers( words[i] );
				}
				return 1;
			}
			return 0;
		}
		return 0;
	}
	return 0;
}

int handle_time( char* words[] ) {

	if( ! words[1] ) {

		char buf[25];
		memset(buf,0,25);
		get_timestamp(buf);
		printf( "%s\n", buf );
		return 1;
	}

	if( words[1] ) {
		time_t epoch = (time_t)atoi( words[1] );
		char* localtime = strdup( ctime( &epoch ) );
		printf( "%s => %s", words[1], localtime );
		free(localtime);
		return 1;
	}

	return 0;

}

		

int router_query_servers( char* router_server ) {

	if( ! router_server || strlen(router_server) == 0 ) 
		return 0;

	char rbuf[256];
	memset(rbuf,0,256);
	sprintf(rbuf,"router@%s/router", router_server );
		
	transport_message* send = 
		message_init( "servers", NULL, NULL, rbuf, NULL );
	message_set_router_info( send, NULL, NULL, NULL, "query", 0 );

	client_send_message( client, send );
	message_free( send );

	transport_message* recv = client_recv( client, -1 );
	if( recv == NULL )
		fprintf(stderr, "NULL message received from router\n");
	
	printf( 
			"---------------------------------------------------------------------------------\n"
			"Received from 'server' query on %s\n"
			"---------------------------------------------------------------------------------\n"
			"original reg time | latest reg time | last used time | class | server\n"
			"---------------------------------------------------------------------------------\n"
			"%s"
			"---------------------------------------------------------------------------------\n"
			, router_server, recv->body );

	message_free( recv );
	
	return 1;
}
		
void print_help() {

	printf(
			"---------------------------------------------------------------------------------\n"
			"Commands:\n"
			"---------------------------------------------------------------------------------\n"
			"router query servers <server1 [, server2, ...]>\n"
			"time\n"					
			"time <timestamp>\n"	
			"---------------------------------------------------------------------------------\n"
			);

}
