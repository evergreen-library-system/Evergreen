#include "socket_bundle.h"

int count = 0;
void printme(void* blob, socket_manager* mgr, 
		int sock_fd, char* data, int parent_id) {

	fprintf(stderr, "Got data from socket %d with parent %d => %s", 
			sock_fd, parent_id, data );

	socket_send(sock_fd, data);

	if(count++ > 2) {
//		socket_disconnect(mgr, sock_fd);
		_socket_print_list(mgr);
		socket_manager_free(mgr);
		exit(0);
	}
}

int main(int argc, char* argv[]) {
	socket_manager* manager = safe_malloc(sizeof(socket_manager));
	int port = 11000;
	if(argv[1])
		port = atoi(argv[1]);

	manager->data_received = &printme;
	socket_open_tcp_server(manager, port);

	while(1)
		socket_wait_all(manager, -1);

	return 0;
}
