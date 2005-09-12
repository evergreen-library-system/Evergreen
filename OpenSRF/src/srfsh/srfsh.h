#include "opensrf/transport_client.h"
#include "opensrf/osrf_message.h"
#include "opensrf/osrf_app_session.h"
#include <time.h>
#include <sys/timeb.h>
#include <sys/types.h>
#include <sys/wait.h>

#include "utils.h"
#include "logging.h"

#include <signal.h>

#include <stdio.h>
#include <readline/readline.h>
#include <readline/history.h>




#define SRFSH_PORT 5222
#define COMMAND_BUFSIZE 4096


/* shell prompt */
char* prompt = "srfsh# "; 

char* history_file = NULL;

int child_dead = 0;

char* login_session = NULL;

/* true if we're pretty printing json results */
int pretty_print = 1;
/* true if we're bypassing 'less' */
int raw_print = 0;

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
int handle_exec(char* words[], int new_shell);
int handle_set( char* words[]);
int handle_print( char* words[]);
int send_request( char* server, 
		char* method, growing_buffer* buffer, int relay );
int parse_error( char* words[] );
int router_query_servers( char* server );
int srfsh_client_connect();
int print_help();
char* tabs(int count);
void sig_child_handler( int s );
void sig_int_handler( int s );

int load_history();
int handle_math( char* words[] );
int do_math( int count, int style );
int handle_introspect(char* words[]);
int handle_login( char* words[]);
