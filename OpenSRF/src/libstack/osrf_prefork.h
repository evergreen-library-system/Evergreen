#include <sys/types.h>
#include <sys/time.h>
#include <unistd.h>
#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include <sys/select.h>
#include <sys/wait.h>

#include "utils.h"
#include "opensrf/transport_message.h"
#include "osrf_stack.h"
#include "osrf_settings.h"

#define READ_BUFSIZE 4096
#define MAX_BUFSIZE 10485760 /* 10M enough? ;) */
#define ABS_MAX_CHILDREN 256 

/* we receive data.  we find the next child in
	line that is available.  pass the data down that childs pipe and go
	back to listening for more data.
	when we receive SIGCHLD, we check for any dead children and clean up
	their respective prefork_child objects, close pipes, etc.

	we build a select fd_set with all the child pipes (going to the parent) 
	when a child is done processing a request, it writes a small chunk of 
	data to the parent to alert the parent that the child is again available 
	*/

struct prefork_simple_struct {
	int max_requests;
	int min_children;
	int max_children;
	int fd;
	int data_to_child;
	int data_to_parent;
	int current_num_children;
	char* appname;
	struct prefork_child_struct* first_child;
	transport_client* connection;
};
typedef struct prefork_simple_struct prefork_simple;

struct prefork_child_struct {
	pid_t pid;
	int read_data_fd;
	int write_data_fd;
	int read_status_fd;
	int write_status_fd;
	int min_children;
	int available;
	int max_requests;
	char* appname;
	struct prefork_child_struct* next;
	transport_client* connection;
};

typedef struct prefork_child_struct prefork_child;

int osrf_prefork_run(char* appname);

prefork_simple*  prefork_simple_init( transport_client* client, 
	int max_requests, int min_children, int max_children );

prefork_child*  launch_child( prefork_simple* forker );
void prefork_launch_children( prefork_simple* forker );

void prefork_run(prefork_simple* forker);

void add_prefork_child( prefork_simple* forker, prefork_child* child );
prefork_child* find_prefork_child( prefork_simple* forker, pid_t pid );
void del_prefork_child( prefork_simple* forker, pid_t pid );

void check_children( prefork_simple* forker );

void prefork_child_process_request(prefork_child*, char* data);
void prefork_child_init_hook(prefork_child*);

prefork_child* prefork_child_init( 
		int max_requests, int read_data_fd, int write_data_fd, 
		int read_status_fd, int write_status_fd );

/* listens on the 'data_to_child' fd and wait for incoming data */
void prefork_child_wait( prefork_child* child );

int prefork_free( prefork_simple* );
int prefork_child_free( prefork_child* );


