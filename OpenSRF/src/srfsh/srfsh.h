#include "opensrf/transport_client.h"
#include "opensrf/generic_utils.h"
#include "opensrf/osrf_message.h"
#include "opensrf/osrf_app_session.h"
#include <time.h>
#include <sys/timeb.h>

#include <signal.h>

#include <stdio.h>
#include <readline/readline.h>
#include <readline/history.h>


#define SRFSH_PORT 5222
#define COMMAND_BUFSIZE 12


/* shell prompt */
char* prompt = "srfsh# "; 

char* history_file = NULL;

int child_dead = 0;

/* true if we're pretty printing json results */
int pretty_print = 1;

/* our jabber connection */
transport_client* client = NULL; 

/* the last result we received */
osrf_message* last_result = NULL;

/* functions */
int parse_request( char* request );

/* handles router requests */
int handle_router( char* words[] );

/* utility method for print time data */
int handle_time( char* words[] );

/* handles app level requests */
int handle_request( char* words[], int relay );
int handle_exec(char* words[]);
int handle_set( char* words[]);
int handle_print( char* words[]);
int send_request( char* server, 
		char* method, growing_buffer* buffer, int relay );
int parse_error( char* words[] );
int router_query_servers( char* server );
int srfsh_client_connect();
int print_help();
char* json_printer( json* object );
char* tabs(int count);
void sig_child_handler( int s );
void sig_int_handler( int s );

int load_history();
int handle_math( char* words[] );
int do_math( int count, int style );
int handle_introspect(char* words[]);

