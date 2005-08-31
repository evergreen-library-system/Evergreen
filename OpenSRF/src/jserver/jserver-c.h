#include "opensrf/utils.h"
#include "opensrf/logging.h"
#include "opensrf/socket_bundle.h"
#include "jserver-c_session.h"
#include "jstrings.h"



struct jclient_node_struct {
	int id;
	char* addr;
	struct jclient_node_struct* next;
	jserver_session* session;
	struct jserver_struct* parent;
};
typedef struct jclient_node_struct jclient_node;

struct jserver_struct {
	jclient_node* client;
	socket_manager* mgr;
};
typedef struct jserver_struct jserver;

/* allocats and sets up a new jserver */
jserver* jserver_init();

void jserver_socket_closed(void* blob, int sock_id);

/* disconnects all client, deallocates the server and all clients */
void jserver_free();

/* opens the inet and unix sockets that we're listening on 
	listen_ip is the IP address the server should listen on.
	if listen_ip is NULL, jserver will bind to all local IP's. 
	if(port < 1) no inet socket is opened
	if unix_path == NULL no unix socket is opened
	returns -1 on error */
int jserver_connect(jserver* js, int port, char* listen_ip, char* unix_path);

/* allocates a new client node */
jclient_node* _new_jclient_node(int id);

void _free_jclient_node(jclient_node* node);

int _jserver_push_client_data(jclient_node* node, char* data);

void jclient_on_parse_error(void* blob, jserver_session* session);

/* called when a newly connected client reveals its address */
void jserver_client_from_found(void* blob, char* from);
void jserver_client_login_init(void* blob, char* reply);
void jserver_client_login_ok(void* blob);
void jserver_client_finish(void* blob);

/* allocates a new client node and adds it to the set */
jclient_node* _jserver_add_client(jserver* js, int id);

/* removes and frees a client node */
void _jserver_remove_client(jserver* js, char* addr);

void _jserver_remove_client_id(jserver* js, int id);

/* finds a client node by addr */
jclient_node* jserver_find_client(jserver* js, char* addr);

jclient_node* jserver_find_client_id(jserver* js, int id);

/* sends msg to client at 'to_addr'. from_id is the id
	of the sending client (if from_id > 0). used for error replies */
int jserver_send(jserver* js, int from_id, char* to_addr, const char* msg_xml);

/* send the data to the client with client_id */
int jserver_send_id(int client_id, const char* msg_xml);

/* waits for any incoming data */
int jserver_wait(jserver* js);

/* handles all incoming socket data */
void jserver_handle_request(void* js, 
	socket_manager* mgr, int sock_id, char* data, int parent_id ); 


/* called by the jserver_session when any client has a 
	complete message parsed and ready to forward on */
void jserver_client_handle_msg( 
		void* blob, char* xml, char* from, char* to );
