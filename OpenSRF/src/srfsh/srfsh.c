#include "srfsh.h"

int is_from_script = 0;
FILE* shell_writer = NULL;
FILE* shell_reader = NULL;

int main( int argc, char* argv[] ) {

	/* --------------------------------------------- */
	/* see if they have a .srfsh.xml in their home directory */
	char* home = getenv("HOME");
	int l = strlen(home) + 36;
	char fbuf[l];
	memset(fbuf, 0, l);
	sprintf(fbuf,"%s/.srfsh.xml",home);
	
	//osrfLogInit( OSRF_LOG_TYPE_SYSLOG, "srfsh", 

	if(!access(fbuf, R_OK)) {
		if( ! osrf_system_bootstrap_client(fbuf, "srfsh") ) {
			osrfLogError( "Unable to bootstrap client for requests");
			return -1;
		}

	} else {
		osrfLogError( "No Config file found at %s", fbuf );
		return -1;
	}

	if(argc > 1) {
		/* for now.. the first arg is used as a script file for processing */
		int f;
		if( (f = open(argv[1], O_RDONLY)) == -1 ) {
			osrfLogError("Unable to open file %s for reading, exiting...", argv[1]);
			return -1;
		}

		if(dup2(f, STDIN_FILENO) == -1) {
			osrfLogError("Unable to duplicate STDIN, exiting...");
			return -1;
		}

		close(f);
		is_from_script = 1;
	}
		
	/* --------------------------------------------- */
	load_history();


	client = osrf_system_get_transport_client();

	/* open the shell handle */
	shell_writer = popen( "bash", "w");
	//shell_reader = popen( "bash", "r");

	/* main process loop */
	char* request;
	while((request=readline(prompt))) {

		if( !strcmp(request, "exit") || !strcmp(request,"quit")) 
			break; 

		char* req_copy = strdup(request);

		parse_request( req_copy ); 
		if( request && strlen(request) > 1 ) {
			add_history(request);
		}

		free(request);
		free(req_copy);

		fflush(shell_writer);
		fflush(stderr);
		fflush(stdout);
	}

	if(history_file != NULL )
		write_history(history_file);

	free(request);

	osrf_system_shutdown();
	return 0;
}

void sig_child_handler( int s ) {
	child_dead = 1;
}

/*
void sig_int_handler( int s ) {
	printf("\n");
	caught_sigint = 1;
	signal(SIGINT,sig_int_handler);
}
*/

int load_history() {

	char* home = getenv("HOME");
	int l = strlen(home) + 24;
	char fbuf[l];

	memset(fbuf, 0, l);
	sprintf(fbuf,"%s/.srfsh_history",home);
	history_file = strdup(fbuf);

	if(!access(history_file, W_OK | R_OK )) {
		history_length = 999;
		read_history(history_file);
	}
	return 1;
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

	fprintf( stderr, "???: %s\n", buffer );
	return 0;

}


int parse_request( char* request ) {

	if( request == NULL )
		return 0;

	int ret_val = 0;
	int i = 0;
	char* words[COMMAND_BUFSIZE]; 
	memset(words,0,COMMAND_BUFSIZE);
	char* req = request;

	char* cur_tok = strtok( req, " " );

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

	/*
	else if( !strcmp(words[0],"time") ) 
		ret_val = handle_time( words );
		*/

	else if (!strcmp(words[0],"request"))
		ret_val = handle_request( words, 0 );

	else if (!strcmp(words[0],"relay"))
		ret_val = handle_request( words, 1 );

	else if (!strcmp(words[0],"help"))
		ret_val = print_help();

	else if (!strcmp(words[0],"set"))
		ret_val = handle_set(words);

	else if (!strcmp(words[0],"print"))
		ret_val = handle_print(words);

	else if (!strcmp(words[0],"math_bench"))
		ret_val = handle_math(words);

	else if (!strcmp(words[0],"introspect"))
		ret_val = handle_introspect(words);

	else if (!strcmp(words[0],"login"))
		ret_val = handle_login(words);

	else if (words[0][0] == '!')
		ret_val = handle_exec( words, 1 );

	if(!ret_val) {
		#ifdef EXEC_DEFAULT
			return handle_exec( words, 0 );
		#else
			return parse_error( words );
		#endif
	}

	return 1;

}


int handle_introspect(char* words[]) {

	if(words[1] && words[2]) {
		fprintf(stderr, "--> %s\n", words[1]);
		char buf[256];
		memset(buf,0,256);
		sprintf( buf, "request %s opensrf.system.method %s", words[1], words[2] );
		return parse_request( buf );

	} else {
	
		if(words[1]) {
			fprintf(stderr, "--> %s\n", words[1]);
			char buf[256];
			memset(buf,0,256);
			sprintf( buf, "request %s opensrf.system.method.all", words[1] );
			return parse_request( buf );
		}
	}

	return 0;
}


int handle_login( char* words[]) {

	if( words[1] && words[2]) {

		char* username = words[1];
		char* password = words[2];

		char buf[256];
		memset(buf,0,256);

		char buf2[256];
		memset(buf2,0,256);

		sprintf( buf, 
				"request open-ils.auth open-ils.auth.authenticate.init \"%s\"", username );
		parse_request(buf); 

		char* hash;
		if(last_result && last_result->_result_content) {
			jsonObject* r = last_result->_result_content;
			hash = jsonObjectGetString(r);
		} else return 0;


		char* pass_buf = md5sum(password);

		char both_buf[256];
		memset(both_buf,0,256);
		sprintf(both_buf,"%s%s",hash, pass_buf);

		char* mess_buf = md5sum(both_buf);

		sprintf( buf2,
				"request open-ils.auth open-ils.auth.authenticate.complete \"%s\", \"%s\", \"opac\"", 
				username, mess_buf );

		free(pass_buf);
		free(mess_buf);

		parse_request( buf2 );

		jsonObject* x = last_result->_result_content;
		if(x) {
			char* authtoken = jsonObjectGetString(jsonObjectGetKey(x, "authtoken"));
			if(authtoken) login_session = strdup(authtoken);
			else login_session = NULL;
		}
		else login_session = NULL;

		printf("Login Session: %s\n", login_session );
		
		return 1;

	}

	return 0;
}

int handle_set( char* words[]) {

	char* variable;
	if( (variable=words[1]) ) {

		char* val;
		if( (val=words[2]) ) {

			if(!strcmp(variable,"pretty_print")) {
				if(!strcmp(val,"true")) {
					pretty_print = 1;
					printf("pretty_print = true\n");
					return 1;
				} 
				if(!strcmp(val,"false")) {
					pretty_print = 0;
					printf("pretty_print = false\n");
					return 1;
				} 
			}

			if(!strcmp(variable,"raw_print")) {
				if(!strcmp(val,"true")) {
					raw_print = 1;
					printf("raw_print = true\n");
					return 1;
				} 
				if(!strcmp(val,"false")) {
					raw_print = 0;
					printf("raw_print = false\n");
					return 1;
				} 
			}

		}
	}

	return 0;
}


int handle_print( char* words[]) {

	char* variable;
	if( (variable=words[1]) ) {
		if(!strcmp(variable,"pretty_print")) {
			if(pretty_print) {
				printf("pretty_print = true\n");
				return 1;
			} else {
				printf("pretty_print = false\n");
				return 1;
			}
		}

		if(!strcmp(variable,"login")) {
			printf("login session = %s\n", login_session );
			return 1;
		}

	}
	return 0;
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


/* if new shell, spawn a new child and subshell to do the work,
	otherwise pipe the request to the currently open (piped) shell */
int handle_exec(char* words[], int new_shell) {

	if(!words[0]) return 0;

	if( words[0] && words[0][0] == '!') {
		int len = strlen(words[0]);
		char command[len];
		memset(command,0,len);
	
		int i; /* chop out the ! */
		for( i=1; i!= len; i++) {
			command[i-1] = words[0][i];
		}
	
		free(words[0]);
		words[0] = strdup(command);
	}

	if(new_shell) {
		signal(SIGCHLD, sig_child_handler);

		if(fork()) {
	
			waitpid(-1, 0, 0);
			if(child_dead) {
				signal(SIGCHLD,sig_child_handler);
				child_dead = 0;
			}
	
		} else {
			execvp( words[0], words );
			exit(0);
		}

	} else {


		growing_buffer* b = buffer_init(64);
		int i = 0;
		while(words[i]) 
			buffer_fadd( b, "%s ", words[i++] );
	
		buffer_add( b, "\n");
	
		//int reader;
		//int reader = dup2(STDOUT_FILENO, reader);
		//int reader = dup(STDOUT_FILENO);
		//close(STDOUT_FILENO);

		fprintf( shell_writer, b->buf );
		buffer_free(b);
	
		fflush(shell_writer);
		usleep(1000);

		/*
		char c[4096];
		bzero(c, 4096);
		read( reader, c, 4095 );
		fprintf(stderr, "read %s", c);
		dup2(reader, STDOUT_FILENO);
		*/

	}

	
	return 1;
}


int handle_request( char* words[], int relay ) {

	if(!client)
		return 1;

	if(words[1]) {
		char* server = words[1];
		char* method = words[2];
		int i;
		growing_buffer* buffer = NULL;
		if(!relay) {
			buffer = buffer_init(128);
			buffer_add(buffer, "[");
			for(i = 3; words[i] != NULL; i++ ) {
				/* removes trailing semicolon if user accidentally enters it */
				if( words[i][strlen(words[i])-1] == ';' )
					words[i][strlen(words[i])-1] = '\0';
				buffer_add( buffer, words[i] );
				buffer_add(buffer, " ");
			}
			buffer_add(buffer, "]");
		}

		return send_request( server, method, buffer, relay );
	} 

	return 0;
}

int send_request( char* server, 
		char* method, growing_buffer* buffer, int relay ) {
	if( server == NULL || method == NULL )
		return 0;

	jsonObject* params = NULL;
	if( !relay ) {
		if( buffer != NULL && buffer->n_used > 0 ) 
			params = json_parse_string(buffer->buf);
	} else {
		if(!last_result || ! last_result->_result_content) { 
			printf("We're not going to call 'relay' with no result params\n");
			return 1;
		}
		else {
			jsonObject* o = jsonNewObject(NULL);
			jsonObjectPush(o, last_result->_result_content );
			params = o;
		}
	}


	if(buffer->n_used > 0 && params == NULL) {
		fprintf(stderr, "JSON error detected, not executing\n");
		return 1;
	}

	osrf_app_session* session = osrf_app_client_session_init(server);

	if(!osrf_app_session_connect(session)) {
		osrfLogWarning( "Unable to connect to remote service %s\n", server );
		return 1;
	}

	double start = get_timestamp_millis();
	//int req_id = osrf_app_session_make_request( session, params, method, 1, NULL );
	int req_id = osrf_app_session_make_req( session, params, method, 1, NULL );


	osrf_message* omsg = osrf_app_session_request_recv( session, req_id, 60 );

	if(!omsg) 
		printf("\nReceived no data from server\n");
	
	
	signal(SIGPIPE, SIG_IGN);

	FILE* less; 
	if(!is_from_script) less = popen( "less -EX", "w");
	else less = stdout;

	if( less == NULL ) { less = stdout; }

	growing_buffer* resp_buffer = buffer_init(4096);

	while(omsg) {

		if(raw_print) {

			if(omsg->_result_content) {
	
				osrf_message_free(last_result);
				last_result = omsg;
	
				char* content;
	
				if( pretty_print && omsg->_result_content ) {
					char* j = jsonObjectToJSON(omsg->_result_content);
					//content = json_printer(j); 
					content = jsonFormatString(j);
					free(j);
				} else
					content = jsonObjectGetString(omsg->_result_content);
	
				printf( "\nReceived Data: %s\n", content ); 
				free(content);
	
			} else {

				char code[16];
				memset(code, 0, 16);
				sprintf( code, "%d", omsg->status_code );
				buffer_add( resp_buffer, code );

				printf( "\nReceived Exception:\nName: %s\nStatus: %s\nStatus: %s\n", 
						omsg->status_name, omsg->status_text, code );

				fflush(stdout);
			}

		} else {

			if(omsg->_result_content) {
	
				osrf_message_free(last_result);
				last_result = omsg;
	
				char* content;
	
				if( pretty_print && omsg->_result_content ) {
					char* j = jsonObjectToJSON(omsg->_result_content);
					//content = json_printer(j); 
					content = jsonFormatString(j);
					free(j);
				} else
					content = jsonObjectGetString(omsg->_result_content);
	
				buffer_add( resp_buffer, "\nReceived Data: " ); 
				buffer_add( resp_buffer, content );
				buffer_add( resp_buffer, "\n" );
				free(content);
	
			} else {
	
				buffer_add( resp_buffer, "\nReceived Exception:\nName: " );
				buffer_add( resp_buffer, omsg->status_name );
				buffer_add( resp_buffer, "\nStatus: " );
				buffer_add( resp_buffer, omsg->status_text );
				buffer_add( resp_buffer, "\nStatus: " );
				char code[16];
				memset(code, 0, 16);
				sprintf( code, "%d", omsg->status_code );
				buffer_add( resp_buffer, code );
			}
		}


		omsg = osrf_app_session_request_recv( session, req_id, 5 );

	}

	double end = get_timestamp_millis();

	fprintf( less, resp_buffer->buf );
	buffer_free( resp_buffer );
	fprintf( less, "\n------------------------------------\n");
	if( osrf_app_session_request_complete( session, req_id ))
		fprintf(less, "Request Completed Successfully\n");


	fprintf(less, "Request Time in seconds: %.6f\n", end - start );
	fprintf(less, "------------------------------------\n");

	pclose(less); 

	osrf_app_session_request_finish( session, req_id );
	osrf_app_session_disconnect( session );
	osrf_app_session_destroy( session );


	return 1;


}

/*
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
*/

		

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
	if( recv == NULL ) {
		fprintf(stderr, "NULL message received from router\n");
		return 1;
	}
	
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
			"!<command> [args] - Forks and runs the given command in the shell\n"
			"time			- Prints the current time\n"					
			"time <timestamp>	- Formats seconds since epoch into readable format\n"	
			"set <variable> <value> - set a srfsh variable (e.g. set pretty_print true )\n"
			"print <variable>		- Displays the value of a srfsh variable\n"
			"---------------------------------------------------------------------------------\n"

			"router query servers <server1 [, server2, ...]>\n"
			"	- Returns stats on connected services\n"
			"\n"
			"\n"
			"request <service> <method> [ <json formatted string of params> ]\n"
			"	- Anything passed in will be wrapped in a json array,\n"
			"		so add commas if there is more than one param\n"
			"\n"
			"\n"
			"relay <service> <method>\n"
			"	- Performs the requested query using the last received result as the param\n"
			"\n"
			"\n"
			"math_bench <num_batches> [0|1|2]\n"
			"	- 0 means don't reconnect, 1 means reconnect after each batch of 4, and\n"
			"		 2 means reconnect after every request\n"
			"\n"
			"introspect <service>\n"
			"	- prints the API for the service\n"
			"\n"
			"\n"
			"---------------------------------------------------------------------------------\n"
			" Commands for Open-ILS\n"
			"---------------------------------------------------------------------------------\n"
			"login <username> <password>\n"
			"	-	Logs into the 'server' and displays the session id\n"
			"	- To view the session id later, enter: print login\n"
			"---------------------------------------------------------------------------------\n"
			"\n"
			"\n"
			"Note: long output is piped through 'less'.  To search in 'less', type: /<search>\n"
			"---------------------------------------------------------------------------------\n"
			"\n"
			);

	return 1;
}



char* tabs(int count) {
	growing_buffer* buf = buffer_init(24);
	int i;
	for(i=0;i!=count;i++)
		buffer_add(buf, "  ");

	char* final = buffer_data( buf );
	buffer_free( buf );
	return final;
}

int handle_math( char* words[] ) {
	if( words[1] )
		return do_math( atoi(words[1]), 0 );
	return 0;
}


int do_math( int count, int style ) {

	osrf_app_session* session = osrf_app_client_session_init(  "opensrf.math" );

	jsonObject* params = json_parse_string("[]");
	jsonObjectPush(params,jsonNewObject("1"));
	jsonObjectPush(params,jsonNewObject("2"));

	char* methods[] = { "add", "sub", "mult", "div" };
	char* answers[] = { "3", "-1", "2", "0.500000" };

	float times[ count * 4 ];
	memset(times,0,count*4);

	int k;
	for(k=0;k!=100;k++) {
		if(!(k%10)) 
			fprintf(stderr,"|");
		else
			fprintf(stderr,".");
	}

	fprintf(stderr,"\n\n");

	int running = 0;
	int i;
	for(i=0; i!= count; i++) {

		int j;
		for(j=0; j != 4; j++) {

			++running;

			double start = get_timestamp_millis();
			int req_id = osrf_app_session_make_req( session, params, methods[j], 1, NULL );
			osrf_message* omsg = osrf_app_session_request_recv( session, req_id, 5 );
			double end = get_timestamp_millis();

			times[(4*i) + j] = end - start;

			if(omsg) {
	
				if(omsg->_result_content) {
					char* jsn = jsonObjectToJSON(omsg->_result_content);
					if(!strcmp(jsn, answers[j]))
						fprintf(stderr, "+");
					else
						fprintf(stderr, "\n![%s] - should be %s\n", jsn, answers[j] );
					free(jsn);
				}


				osrf_message_free(omsg);
		
			} else { fprintf( stderr, "\nempty message for tt: %d\n", req_id ); }

			osrf_app_session_request_finish( session, req_id );

			if(style == 2)
				osrf_app_session_disconnect( session );

			if(!(running%100))
				fprintf(stderr,"\n");
		}

		if(style==1)
			osrf_app_session_disconnect( session );
	}

	osrf_app_session_destroy( session );
	jsonObjectFree(params);

	int c;
	float total = 0;
	for(c=0; c!= count*4; c++) 
		total += times[c];

	float avg = total / (count*4); 
	fprintf(stderr, "\n      Average round trip time: %f\n", avg );

	return 1;
}
