#include "socket_bundle.h"

/* -------------------------------------------------------------------- 
	Test Code 
	-------------------------------------------------------------------- */
/*
int count = 0;
void printme(void* blob, socket_manager* mgr, 
		int sock_fd, char* data, int parent_id) {

	fprintf(stderr, "Got data from socket %d with parent %d => %s", 
			sock_fd, parent_id, data );

	socket_send(sock_fd, data);

	if(count++ > 2) {
		socket_disconnect(mgr, sock_fd);
		_socket_print_list(mgr);
	}
}

int main(int argc, char* argv[]) {
	socket_manager manager;
	memset(&manager, 0, sizeof(socket_manager));
	int port = 11000;
	if(argv[1])
		port = atoi(argv[1]);

	manager.data_received = &printme;
	socket_open_tcp_server(&manager, port);

	while(1)
		socket_wait_all(&manager, -1);

	return 0;
}
*/
/* -------------------------------------------------------------------- */


/*
int debug_handler(char* msg, ...) {
	va_list args;
	va_start(args, msg);
	vfprintf(stderr, msg, args);
	va_end(args);
	fprintf( stderr, "\n" );
	return -1;
}

int warning_handler(char* msg, ...) {
	va_list args;
	va_start(args, msg);
	vfprintf(stderr, msg, args);
	va_end(args);
	fprintf( stderr, "\n" );
	return -1;
}
*/


socket_node* _socket_add_node(socket_manager* mgr, 
		int endpoint, int addr_type, int sock_fd, int parent_id ) {

	if(mgr == NULL) return NULL;
	debug_handler("Adding socket node with fd %d", sock_fd);
	socket_node* new_node = safe_malloc(sizeof(socket_node));

	new_node->endpoint	= endpoint;
	new_node->addr_type	= addr_type;
	new_node->sock_fd		= sock_fd;
	new_node->next			= NULL;
	new_node->parent_id = 0;
	if(parent_id > 0)
		new_node->parent_id = parent_id;

	new_node->next			= mgr->socket;
	mgr->socket				= new_node;
	return new_node;
}

/* creates a new server socket node and adds it to the socket set.
	returns new socket fd on success.  -1 on failure.
	socket_type is one of INET or UNIX  */
int socket_open_tcp_server(socket_manager* mgr, int port) {

	if( mgr == NULL ) return warning_handler("socket_open_tcp_server(): NULL mgr"); 

	int sock_fd;
	struct sockaddr_in server_addr;

	sock_fd = socket(AF_INET, SOCK_STREAM, 0);

	if(sock_fd < 0) 
		return warning_handler("tcp_server_connect(): Unable to create socket");

	server_addr.sin_family = AF_INET;
	server_addr.sin_addr.s_addr = htonl(INADDR_ANY);
	server_addr.sin_port = htons(port);

	if(bind( sock_fd, (struct sockaddr*) &server_addr, sizeof(server_addr)) < 0)
		return warning_handler("tcp_server_connect(): cannot bind to port %d", port );

	if(listen(sock_fd, 20) == -1) 
		return warning_handler("tcp_server_connect(): listen() returned error");

	_socket_add_node(mgr, SERVER_SOCKET, INET, sock_fd, 0);
	return sock_fd;
}

int socket_open_unix_server(socket_manager* mgr, char* path) {
	if(mgr == NULL || path == NULL) return -1;

	debug_handler("opening unix socket at %s", path);
	int sock_fd;
	struct sockaddr_un server_addr;

	sock_fd = socket(AF_UNIX, SOCK_STREAM, 0);
	if(sock_fd < 0)
		return warning_handler("socket_open_unix_server(): socket() failed");

	server_addr.sun_family = AF_UNIX;
	strcpy(server_addr.sun_path, path);

	if( bind(sock_fd, (struct sockaddr*) &server_addr, 
				sizeof(struct sockaddr_un)) < 0) {
		return warning_handler(
			"socket_open_unix_server(): cannot bind to unix port %s", path );
	}

	if(listen(sock_fd, 20) == -1) 
		return warning_handler("socket_open_unix_server(): listen() returned error");

	debug_handler("unix socket successfully opened");
	_socket_add_node(mgr, SERVER_SOCKET, UNIX, sock_fd, 0);
	return sock_fd;
}



/* creates a client socket and adds it to the socket set.
	returns 0 on success.  -1 on failure.
	socket_type is one of INET or UNIX  */
int socket_open_client(socket_manager* mgr, 
		int socket_type, int port, char* dest_addr) {
	return 0;
}

/* returns the socket_node with the given sock_fd */
socket_node* socket_find_node(socket_manager* mgr, int sock_fd) {
	if(mgr == NULL) return NULL;
	socket_node* node = mgr->socket;
	while(node) {
		if(node->sock_fd == sock_fd)
			return node;
		node = node->next;
	}
	return NULL;
}

/* removes the node with the given sock_fd from the list and frees it */
void socket_remove_node(socket_manager* mgr, int sock_fd) {

	if(mgr == NULL) return;

	debug_handler("removing socket %d", sock_fd);

	socket_node* head = mgr->socket;
	socket_node* tail = head;
	if(head == NULL) return;

	/* if removing the first node in the list */
	if(head->sock_fd == sock_fd) {
		mgr->socket = head->next;
		free(head);
		debug_handler("removing first socket in list");
		return;
	}

	head = head->next;

	/* if removing any other node */
	while(head) {
		if(head->sock_fd == sock_fd) {
			tail->next = head->next;
			free(head);
			return;
		}
		tail = head;
		head = head->next;
	}
}



void _socket_print_list(socket_manager* mgr) {
	if(mgr == NULL) return;
	socket_node* node = mgr->socket;
	debug_handler("socket_node list: [");
	while(node) {
		debug_handler("sock_fd: %d | parent_id: %d", 
				node->sock_fd, node->parent_id);
		node = node->next;
	}
	debug_handler("]");
}

/* sends the given data to the given socket */
int socket_send(int sock_fd, const char* data) {
	debug_handler( "socket_bundle sending to %d data %s",
		sock_fd, data);

	signal(SIGPIPE, SIG_IGN); /* in case a unix socket was closed */
	if( send( sock_fd, data, strlen(data), 0 ) < 0 ) {
		return warning_handler( "tcp_server_send(): Error sending data" );
	}

	return 0;
}

/* disconnects the node with the given sock_fd and removes
	it from the socket set */
void socket_disconnect(socket_manager* mgr, int sock_fd) {

	debug_handler("Closing socket %d", sock_fd);
	if( close( sock_fd ) == -1 ) 
		warning_handler( "socket_disconnect(): Error closing socket, removing anyway" );

	if(mgr != NULL) 
		socket_remove_node(mgr, sock_fd);
	
}


/* we assume that if select() fails, the socket is no longer valid */
int socket_connected(int sock_fd) {
	fd_set read_set;
	FD_ZERO( &read_set );
	FD_SET( sock_fd, &read_set );
	if( select( sock_fd + 1, &read_set, NULL, NULL, NULL) == -1 ) 
		return 0;
	return 1;

}

int socket_wait(socket_manager* mgr, int timeout, int sock_fd) {
	return 0;
}


int socket_wait_all(socket_manager* mgr, int timeout) {

	if(mgr == NULL) return warning_handler( "tcp_wait(): null mgr" );

	int retval = 0;
	fd_set read_set;
	FD_ZERO( &read_set );

	socket_node* node = mgr->socket;
	int max_fd = 0;
	while(node) {
		//debug_handler("Adding socket %d to select set",node->sock_fd);
		FD_SET( node->sock_fd, &read_set );
		if(node->sock_fd > max_fd) max_fd = node->sock_fd;
		node = node->next;
	}
	max_fd += 1;

	struct timeval tv;
	tv.tv_sec = timeout;
	tv.tv_usec = 0;

	if( timeout == -1 ) {  

		// If timeout is -1, there is no timeout passed to the call to select
		if( (retval = select( max_fd, &read_set, NULL, NULL, NULL)) == -1 ) {
			return warning_handler("Call to select interrupted");
		}

	} else if( timeout != 0 ) { /* timeout of 0 means don't block */

		if( (retval = select( max_fd, &read_set, NULL, NULL, &tv)) == -1 ) {
			return warning_handler( "Call to select interrupted" );
		}
	}

	debug_handler("%d active sockets after select()", retval);
	return _socket_route_data(mgr, retval, &read_set);
}

/* determines if we'er receiving a new client or data
	on an existing client */
int _socket_route_data(
	socket_manager* mgr, int num_active, fd_set* read_set) {

	if(mgr == NULL) return -1;


	/* come back here if someone yanks a socket_node from beneath us */
	while(1) {

		socket_node* node = mgr->socket;
		int handled = 0;
		int status = 0;
		
		while(node && (handled < num_active)) {
	
			int sock_fd = node->sock_fd;
	
			/* does this socket have data? */
			if( FD_ISSET( sock_fd, read_set ) ) {
	
				debug_handler("Socket %d active", sock_fd);
				handled++;
				FD_CLR(sock_fd, read_set);
	
				if(node->endpoint == SERVER_SOCKET) 
					_socket_handle_new_client(mgr, node);
	
				if(node->endpoint == CLIENT_SOCKET ) 
					status = _socket_handle_client_data(mgr, node);
	
				/* someone may have yanked a socket_node out from under 
					us...start over with the first socket */
				if(status == -1)  {
					debug_handler("Backtracking back to start of loop because "
							"of -1 return code from _socket_handle_client_data()");
				}
			}

			if(status == -1) break;
			node = node->next;

		} // is_set

		if(status == 0) break;
		if(status == -1) status = 0;
	} 

	return 0;
}


int _socket_handle_new_client(socket_manager* mgr, socket_node* node) {
	if(mgr == NULL || node == NULL) return -1;

	//struct sockaddr_in client_addr_in; 
	//struct sockaddr_un client_addr_un; 
	//int client_len, new_sock_fd; 

	int new_sock_fd;
	new_sock_fd = accept(node->sock_fd, NULL, NULL);
	if(new_sock_fd < 0)
		return warning_handler("_socket_route_data(): accept() failed");

	if(node->addr_type == INET) {
		_socket_add_node(mgr, CLIENT_SOCKET, INET, new_sock_fd, node->sock_fd);
		debug_handler("Adding new INET client for %d", node->sock_fd);

	} else if(node->addr_type == UNIX) {
		_socket_add_node(mgr, CLIENT_SOCKET, UNIX, new_sock_fd, node->sock_fd);
		debug_handler("Adding new UNIX client for %d", node->sock_fd);
	}

	return 0;
}


int _socket_handle_client_data(socket_manager* mgr, socket_node* node) {
	if(mgr == NULL || node == NULL) return -1;

	char buf[BUFSIZE];
	int read_bytes;
	int sock_fd = node->sock_fd;

	memset(buf, 0, BUFSIZE);
	set_fl(sock_fd, O_NONBLOCK);
	debug_handler("Gathering client data for %d", node->sock_fd);

	debug_handler("Socket buf before read %s", buf);
	while( (read_bytes = recv(sock_fd, buf, BUFSIZE-1, 0) ) > 0 ) {
		debug_handler("Socket %d Read %d bytes and data: %s", sock_fd, read_bytes, buf);

		/*
		int l = strlen(buf); 
		if(l > 1) {buf[l-1] = '\0';buf[l-2] = '\0';}
		debug_handler("Socket data after cleanup: %s", sock_fd, read_bytes, buf);
		*/


		if(mgr->data_received)
			mgr->data_received(mgr->blob, mgr, sock_fd, buf, node->parent_id);

		memset(buf, 0, BUFSIZE);
	}

	if(socket_find_node(mgr, sock_fd)) {  /* someone may have closed this socket */
		clr_fl(sock_fd, O_NONBLOCK); 
		if(read_bytes < 0) { 
			if( errno != EAGAIN ) 
				warning_handler( " * Error reading socket with errno %d", errno );
		}
	}

	if(read_bytes == 0) {  /* socket closed by client */
		if(mgr->on_socket_closed) {
			mgr->on_socket_closed(mgr->blob, sock_fd);
			return -1;
		}
	}

	return 0;

}


void socket_manager_free(socket_manager* mgr) {
	if(mgr == NULL) return;
	socket_node* tmp;
	while(mgr->socket) {
		tmp = mgr->socket->next;
		socket_disconnect(mgr, mgr->socket->sock_fd);
		mgr->socket = tmp;
	}
	free(mgr);

}
