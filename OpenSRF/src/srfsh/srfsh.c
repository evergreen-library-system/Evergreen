#include "opensrf/transport_client.h"
#include "opensrf/generic_utils.h"
#include "opensrf/osrf_message.h"
#include "opensrf/osrf_app_session.h"
#include <time.h>

#include <stdio.h>
#include <readline/readline.h>
#include <readline/history.h>


#define SRFSH_PORT 5222
#define COMMAND_BUFSIZE 12


char* prompt = "srfsh# ";
char* last_request;
transport_client* client = NULL;

int parse_request( char* request );
int handle_router( char* words[] );
int handle_time( char* words[] );
int handle_request( char* words[] );
int send_request( char* server, char* method, growing_buffer* buffer );
int parse_error( char* words[] );
int router_query_servers( char* server );
int srfsh_client_connect();
int print_help();
char* json_printer( json* object );
char* tabs(int count);

int main( int argc, char* argv[] ) {

	if( argc < 2 ) 
		fatal_handler( "usage: %s <config_file>", argv[0] );
		
	config_reader_init( "opensrf", argv[1] );	

	if( ! osrf_system_bootstrap_client("srfsh.xml") ) 
		fprintf( stderr, "Unable to bootstrap client for requests\n");

	client = osrf_system_get_transport_client();

	char* request;
	while((request=readline(prompt))) {

		if( !strcmp(request, "exit") || !strcmp(request,"quit")) 
			break; 

		char* req_copy = strdup(request);

		if(parse_request( req_copy ) ) 
			add_history(request);

		free(request);
		free(req_copy);
	}

	free(request);
	client_disconnect( client );
	client_free( client );	
	config_reader_free();	
	log_free();
		
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
	//char* req = strdup(request);
	char* req = request;

	char* cur_tok = strtok( req, " " );

	if( cur_tok == NULL )
		return 0;

	while(cur_tok != NULL) {
		words[i++] = cur_tok;
		cur_tok = strtok( NULL, " " );
	}

	//free(req);

	// not sure why (strtok?), but this is necessary
	memset( words + i, 0, COMMAND_BUFSIZE - i );

	/* pass off to the top level command */
	if( !strcmp(words[0],"router") ) 
		ret_val = handle_router( words );

	else if( !strcmp(words[0],"time") ) 
		ret_val = handle_time( words );

	else if (!strcmp(words[0],"request"))
		ret_val = handle_request( words );

	else if (!strcmp(words[0],"help"))
		return print_help();

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

int handle_request( char* words[] ) {

	if(!client)
		return 1;

	if(words[1]) {
		char* server = words[1];
		char* method = words[2];
		int i;
		growing_buffer* buffer = buffer_init(128);

		buffer_add(buffer, "[");
		for(i = 3; words[i] != NULL; i++ ) {
			buffer_add( buffer, words[i] );
			buffer_add(buffer, " ");
		}
		buffer_add(buffer, "]");

		return send_request( server, method, buffer );
	} 

	return 0;
}

int send_request( char* server, char* method, growing_buffer* buffer ) {
	if( server == NULL || method == NULL )
		return 0;

	json* params = NULL;
	if( buffer != NULL && buffer->n_used > 0 ) 
		params = json_tokener_parse(buffer->buf);

	osrf_app_session* session = osrf_app_client_session_init(server);
	double start = get_timestamp_millis();

	if(!osrf_app_session_connect(session)) {
		warning_handler( "Unable to connect to remote service %s\n", server );
		return 1;
	}

	int req_id = osrf_app_session_make_request( session, params, method, 1 );

	osrf_message* omsg = osrf_app_session_request_recv( session, req_id, 8 );

	if(!omsg) 
		printf("Received no data from server\n");
	
	
	while(omsg) {
		if(omsg->result_content) {
			char* content = json_printer( omsg->result_content );
			printf( "Received Data: %s\n",content );
			free(content);
		}
		else
			printf( "Received Message but no result data\n");

		osrf_message_free(omsg);
		omsg = osrf_app_session_request_recv( session, req_id, 5 );
	}


	if( osrf_app_session_request_complete( session, req_id ))
		printf("[Request Completed Successfully]\n");

	double end = get_timestamp_millis();

	printf("Request Time in seconds: %f\n", end - start );

	osrf_app_session_disconnect( session );

	return 1;


}

int handle_time( char* words[] ) {

	if( ! words[1] ) {

		char buf[36];
		memset(buf,0,36);
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
		
int print_help() {

	printf(
			"---------------------------------------------------------------------------------\n"
			"Commands:\n"
			"---------------------------------------------------------------------------------\n"
			"help			- Display this message\n"
			"last			- Re-performs the last command\n"
			"time			- Prints the current time\n"					
			"time <timestamp>	- Formats seconds since epoch into readable format\n"	
			"---------------------------------------------------------------------------------\n"
			"router query servers <server1 [, server2, ...]>\n"
			"	- Returns stats on connected services\n"
			"reqeust <service> <method> [ <json formatted string of params> ]\n"
			"	- Anything passed in will be wrapped in a json array\n"
			"---------------------------------------------------------------------------------\n"
			);

	return 1;
}



char* tabs(int count) {
	growing_buffer* buf = buffer_init(24);
	int i;
	for(i=0;i!=count;i++)
		buffer_add(buf, "   ");

	char* final = buffer_data( buf );
	buffer_free( buf );
	return final;
}

char* json_printer( json* object ) {

	if(object == NULL)
		return NULL;
	char* string = json_object_to_json_string(object);

	growing_buffer* buf = buffer_init(64);
	int i;
	int tab_var = 0;
	for(i=0; i!= strlen(string); i++) {

		if( string[i] == '{' ) {

			buffer_add(buf, "\n");
			char* tab = tabs(tab_var);
			buffer_add(buf, tab);
			free(tab);
			buffer_add( buf, "{");
			tab_var++;
			buffer_add( buf, "\n" );	
			tab = tabs(tab_var);
			buffer_add( buf, tab );	
			free(tab);

		} else if( string[i] == '[' ) {

			buffer_add(buf, "\n");
			char* tab = tabs(tab_var);
			buffer_add(buf, tab);
			free(tab);
			buffer_add( buf, "[");
			tab_var++;
			buffer_add( buf, "\n" );	
			tab = tabs(tab_var);
			buffer_add( buf, tab );	
			free(tab);

		} else if( string[i] == '}' ) {

			tab_var--;
			buffer_add(buf, "\n");
			char* tab = tabs(tab_var);
			buffer_add(buf, tab);
			free(tab);
			buffer_add( buf, "}");
			buffer_add( buf, "\n" );	
			tab = tabs(tab_var);
			buffer_add( buf, tab );	
			free(tab);

		} else if( string[i] == ']' ) {

			tab_var--;
			buffer_add(buf, "\n");
			char* tab = tabs(tab_var);
			buffer_add(buf, tab);
			free(tab);
			buffer_add( buf, "]");
			buffer_add( buf, "\n" );	
			tab = tabs(tab_var);
			buffer_add( buf, tab );	
			free(tab);

		} else {
			char b[2];
			b[0] = string[i];
			b[1] = '\0';
			buffer_add( buf, b ); 
		}

	}

	char* result = buffer_data(buf);
	buffer_free(buf);
	return result;

}
