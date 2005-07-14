#include "jserver-c.h"

/* ------------------------------------------------
	some pre-packaged Jabber XML
	------------------------------------------------ */
static const char* xml_parse_error = "<stream:stream xmlns:stream='http://etherx.jabber.org/streams'" 
	"version='1.0'><stream:error xmlns:stream='http://etherx.jabber.org/streams'>"
	"<xml-not-well-formed xmlns='urn:ietf:params:xml:ns:xmpp-streams'/>"
	"<text xmlns='urn:ietf:params:xml:ns:xmpp-streams'>syntax error</text></stream:error></stream:stream>";

static const char* xml_login_ok = "<iq xmlns='jabber:client' id='asdfjkl' type='result'/>";


jserver* jserver_init() {
	jserver* js					= safe_malloc(sizeof(jserver));
	js->mgr						= safe_malloc(sizeof(socket_manager));
	js->mgr->data_received	= &jserver_handle_request;
	js->mgr->blob				= js;
	js->mgr->on_socket_closed	= &jserver_socket_closed;
	js->client					= NULL;

	return js;
}

void jserver_free(jserver* js) {
	if(js == NULL) return;
	jclient_node* node; 
	while(js->client) {
		node = js->client->next;
		_jserver_remove_client_id(js, js->client->id);
		js->client = node;
	}
	socket_manager_free(js->mgr);
	free(js);
}

void jserver_socket_closed(void* blob, int sock_id) {
	jserver* js = (jserver*) blob;
	if(js == NULL) return;
	info_handler("Removing client %d - site closed socket",sock_id);
	_jserver_remove_client_id(js, sock_id);
}

/* opens the inet and unix sockets that we're listening on */
int jserver_connect(jserver* js, int port, char* unix_path) {
	if(js == NULL || js->mgr == NULL) return -1;
	int status = 0;

	if(port > 0) {
		status = socket_open_tcp_server(js->mgr, port);
		if(status == -1) return status;
	}

	if(unix_path != NULL) {
		status = socket_open_unix_server(js->mgr, unix_path);
		if(status == -1) return status;
	}

	return 0;
}

void _free_jclient_node(jclient_node* node) {
	if(node == NULL) return;
	free(node->addr);
	jserver_session_free(node->session);
	free(node);
}

/* allocates a new client node */
jclient_node* _new_jclient_node(int id) {
	jclient_node* node = safe_malloc(sizeof(jclient_node));
	node->id = id;
	node->addr = NULL;
	node->session = jserver_session_init();
	node->session->blob = node;
	node->session->on_msg_complete = &jserver_client_handle_msg; 
	node->session->on_from_discovered = &jserver_client_from_found;
	node->session->on_login_init = &jserver_client_login_init;
	node->session->on_login_ok = &jserver_client_login_ok;
	node->session->on_client_finish = &jserver_client_finish;
	return node;
}

/* client has sent the end of it's session doc, we may now disconnect */
void jserver_client_finish(void* blob) {
	jclient_node* node = (jclient_node*) blob;
	if(node == NULL) return;
	jserver_send_id(node->id, "</stream:stream>");
	_jserver_remove_client(node->parent, node->addr);

}

void jserver_client_from_found(void* blob, char* from) {
	jclient_node* node = (jclient_node*) blob;
	if(node == NULL || from == NULL) return;

	/* prevent duplicate login - kick off original */
	_jserver_remove_client(node->parent, from);
	info_handler("logged in: %s", from);
	node->addr = strdup(from);
}

void jserver_client_login_init(void* blob, char* reply) {
	debug_handler("here");
	jclient_node* node = (jclient_node*) blob;
	if(node == NULL || reply == NULL) return;
	debug_handler("jserver handling login init");
	jserver_send_id(node->id, reply);
}

void jserver_client_login_ok(void* blob) {
	jclient_node* node = (jclient_node*) blob;
	if(node == NULL) return;
	info_handler("Client logging in ok => %d", node->id);
	jserver_send_id(node->id, xml_login_ok);
}

void jserver_client_handle_msg( 
	void* blob, char* xml, char* from, char* to ) {

	jclient_node* node = (jclient_node*) blob;
	if(node == NULL || xml == NULL || to == NULL) return;
	int from_id = 0;

	jclient_node* from_node = jserver_find_client(node->parent, from);
	if(from_node)
		from_id = from_node->id;


	debug_handler("Client %d received from %s message : %s", 
			node->id, from, xml );

	jserver_send(node->parent, from_id, to, xml);
}

/* allocates a new client node and adds it to the set */
jclient_node* _jserver_add_client(jserver* js, int id) {
	if(js == NULL) return NULL;
	jclient_node* node = _new_jclient_node(id);
	node->next = js->client;
	js->client = node;
	node->parent = js;
	return node;
}


/* removes and frees a client node */
void _jserver_remove_client(jserver* js, char* addr) {
	if(js == NULL || js->client == NULL || addr == NULL) return;

	jclient_node* node = js->client;

	if(node->addr && !strcmp(node->addr,addr)) {
		js->client = node->next;
		debug_handler("Removing the first jserver client");
		socket_disconnect(js->mgr, node->id);
		_free_jclient_node(node);
		return;
	}

	debug_handler("Searching for jclient to remove");
	jclient_node* tail_node = node;
	node = node->next;

	while(node) {
		if(node->addr && !strcmp(node->addr,addr)) {
			tail_node->next = node->next;
			debug_handler("Removing a jserver client");
			socket_disconnect(js->mgr, node->id);
			_free_jclient_node(node);
			return;
		}
		tail_node = node;
		node = node->next;
	}
}


/* removes and frees a client node */
void _jserver_remove_client_id(jserver* js, int id) {
	if(js == NULL || js->client == NULL) return;

	jclient_node* node = js->client;

	if(node->id == id) {
		js->client = node->next;
		debug_handler("Removing the first jserver client");
		socket_disconnect(js->mgr, node->id);
		_free_jclient_node(node);
		return;
	}

	debug_handler("Searching for jclient to remove");
	jclient_node* tail_node = node;
	node = node->next;

	while(node) {
		if(node->id == id) {
			tail_node->next = node->next;
			debug_handler("Removing a jserver client");
			socket_disconnect(js->mgr, node->id);
			_free_jclient_node(node);
			return;
		}
		tail_node = node;
		node = node->next;
	}
}

/* finds a client node by addr */
jclient_node* jserver_find_client(jserver* js, char* addr) {
	if(js == NULL || addr == NULL) return NULL;
	jclient_node* node = js->client;
	while(node) {
		if(node->addr && !strcmp(node->addr, addr)) 
			return node;
		node = node->next;
	}
	return NULL;
}

jclient_node* jserver_find_client_id(jserver* js, int id) {
	if(js == NULL) return NULL;
	jclient_node* node = js->client;
	while(node) {
		if(node->id == id) 
			return node;
		node = node->next;
	}
	return NULL;
}

/* sends msg to client at 'to_addr' */
int jserver_send(jserver* js, int from_id, char* to_addr, const char* msg_xml) {
	debug_handler("sending message to %s : %s", to_addr, msg_xml);
	if(to_addr == NULL || msg_xml == NULL) return -1;

	jclient_node* node = jserver_find_client(js, to_addr);

	if(node == NULL) {
		info_handler("message to non-existent client %s", to_addr);
		if(from_id > 0) {
			jclient_node* from = jserver_find_client_id(js, from_id);

			if(from) {
				info_handler("replying with error...");
				char buf[2048];
				memset(buf, 0, 2048);
				snprintf(buf, 2047, "<message xmlns='jabber:client' type='error' from='%s' "
					"to='%s'><error type='cancel' code='404'><item-not-found "
					"xmlns='urn:ietf:params:xml:ns:xmpp-stanzas'/></error>"
					"<body>NOT ADDING BODY</body></message>", to_addr, from->addr );
				jserver_send_id(from_id, buf);
			}
		}
		return -1;
	}

	return jserver_send_id(node->id, msg_xml);
}

int jserver_send_id(int client_id, const char* msg_xml) {
	if(msg_xml == NULL || client_id < 1) return -1;
	return socket_send(client_id, msg_xml );
}

/* waits for any incoming data */
int jserver_wait(jserver* js) {
	if(js == NULL) return -1;
	while(1) {
		if(socket_wait_all(js->mgr, -1) < 0)
			warning_handler(
				"jserver_wait(): socket_wait_all() returned error");

	}
}


int _jserver_push_client_data(jclient_node* node, char* data) {
	if(node == NULL || data == NULL) return -1;
	return jserver_session_push_data( node->session, data);
}

void jserver_handle_request(void* js_blob, 
	socket_manager* mgr, int sock_id, char* data, int parent_id ) {

	jserver* js = (jserver*) js_blob;

	debug_handler("jsever received data from socket %d (parent %d)", sock_id, parent_id );

	jclient_node* node = jserver_find_client_id(js, sock_id);
	if(!node) {
		debug_handler("We have a new client connection, adding to list");
		node = _jserver_add_client(js, sock_id);
	}

	if(_jserver_push_client_data(node, data) == -1) {
		warning_handler("Client sent bad data, disconnecting...");
		jserver_send_id(node->id, xml_parse_error);
		_jserver_remove_client(js, node->addr);		

	} else {
		debug_handler("Client data successfully parsed");
	}

}




