#include "router.h"
#include <sys/types.h>
#include <signal.h>


char* router_resource;
transport_router_registrar* routt;

void sig_hup_handler( int a ) { 
	router_registrar_free( routt );	
	config_reader_free();	
	log_free();
	free( router_resource );
	exit(0); 
}


int main( int argc, char* argv[] ) {

	if( argc < 2 ) {
		fatal_handler( "Usage: %s <path_to_config_file>", argv[0] );
		exit(0);
	}


	config_reader_init( argv[1] );	
	if( conf_reader == NULL ) fatal_handler( "main(): Config is NULL" ); 

	/* laod the config options */
	char* server			= config_value("//router/transport/server");
	char* port				= config_value("//router/transport/port");
	char* username			= config_value("//router/transport/username");
	char* password			= config_value("//router/transport/password");
	router_resource		= config_value("//router/transport/resource");
	char* con_timeout		= config_value("//router/transport/connect_timeout" );
	char* max_retries		= config_value("//router/transport/max_reconnect_attempts" );

	fprintf(stderr, "Router connecting as \nserver: %s \nport: %s \nuser:%s \nresource:%s\n", 
			server, port, username, router_resource );

	int iport			= atoi( port );
	int con_itimeout	= atoi( con_timeout );
	int max_retries_	= atoi(max_retries);

	if( iport < 1 ) { 
		fatal_handler( "Port is negative or 0" );
		return 99;
	}


	/* build the router_registrar */
	transport_router_registrar* router_registrar = 
		router_registrar_init( server, iport, username, password, router_resource, 0, con_itimeout ); 

	routt = router_registrar;

	free(server);
	free(port);
	free(username);
	free(password);
	free(con_timeout);
	free(max_retries);

	signal(SIGHUP,sig_hup_handler);


	int counter = 0;
	/* wait for incoming... */
	while( ++counter <= max_retries_ ) {

		/* connect to jabber */
		if( router_registrar_connect( router_registrar ) )  {
			info_handler( "Connected..." );
			fprintf(stderr, "- Connected -\n");
			counter = 0;
			listen_loop( router_registrar );
		} else  
			fatal_handler( "Could not connect to Jabber Server" );

		/* this should never happen */
		warning_handler( "Jabber server probably went away, attempting reconnect" );

		sleep(5);
	}


	router_registrar_free( router_registrar );
	config_reader_free();	
	return 1;

}

transport_router_registrar* router_registrar_init( char* server, 
		int port, char* username, char* password, 
		char* resource, int client_timeout, int con_timeout ) {

	if( server == NULL ) { return NULL; }
	
	/* allocate a new router_registrar object */
	size_t size = sizeof( transport_router_registrar );
	transport_router_registrar* router_registrar = (transport_router_registrar*) safe_malloc( size );

	router_registrar->client_timeout	= client_timeout;
	router_registrar->jabber = jabber_connect_init( server, port, username, password, resource, con_timeout );
	return router_registrar;

}

jabber_connect* jabber_connect_init( char* server, 
		int port, char* username, char* password, char* resource, int connect_timeout ) {

	size_t len = sizeof(jabber_connect);
	jabber_connect* jabber = (jabber_connect*) safe_malloc( len );

	jabber->port				= port;
	jabber->connect_timeout	= connect_timeout;

	jabber->server				= strdup(server);
	jabber->username			= strdup(username);
	jabber->password			= strdup(password);
	jabber->resource			= strdup(resource);

	if( jabber->server == NULL || jabber->username == NULL ||
			jabber->password == NULL || jabber->resource == NULL ) {
		fatal_handler( "jabber_init(): Out of Memory" );
		return NULL;
	}

	/* build the transport client */
	jabber->t_client = client_init( jabber->server, jabber->port );

	return jabber;
}

/* connect the router_registrar to jabber */
int router_registrar_connect( transport_router_registrar* router ) {
	return j_connect( router->jabber );
}

/* connect a jabber_connect object jabber */
int j_connect( jabber_connect* jabber ) {
	if( jabber == NULL ) { return 0; }
	return client_connect( jabber->t_client, 
			jabber->username, jabber->password, jabber->resource, jabber->connect_timeout );
}

int fill_fd_set( transport_router_registrar* router, fd_set* set ) {
	
	int max_fd;
	FD_ZERO(set);

	int router_fd = router->jabber->t_client->session->sock_obj->sock_fd;
	max_fd = router_fd;
	FD_SET( router_fd, set );

	server_class_node* cur_node = router->server_class_list;
	while( cur_node != NULL ) {
		int cur_class_fd = cur_node->jabber->t_client->session->sock_obj->sock_fd;
		if( cur_class_fd > max_fd ) 
			max_fd = cur_class_fd;
		FD_SET( cur_class_fd, set );
		cur_node = cur_node->next;
	}

	FD_CLR( 0, set );
	return max_fd;
}


void listen_loop( transport_router_registrar* router ) {

	if( router == NULL )
		return;

	int select_ret;
	int router_fd = router->jabber->t_client->session->sock_obj->sock_fd;
	transport_message* cur_msg;

	while(1) {

		fd_set listen_set;
		int max_fd = fill_fd_set( router, &listen_set );

		if( max_fd < 1 ) 
			fatal_handler( "fill_fd_set return bogus max_fd: %d", max_fd );

		int num_handled = 0;
		info_handler( "Going into select" );

		if( (select_ret=select(max_fd+ 1, &listen_set, NULL, NULL, NULL)) < 0 ) {

			warning_handler( "Select returned error %d", select_ret );
			warning_handler( "Select Error %d on fd %d", errno );
			perror( "Select Error" );
			warning_handler( "Errors: EBADF %d, EINTR %d, EINVAL %d, ENOMEM %d",
					EBADF, EINTR, EINVAL, ENOMEM );
			continue;

		} else {

			info_handler( "Select returned %d", select_ret );
			
			if( FD_ISSET( router_fd, &listen_set ) ) {
				cur_msg = client_recv( router->jabber->t_client, 1 );
				router_registrar_handle_msg( router, cur_msg );
				message_free( cur_msg );
				if( ++num_handled == select_ret ) 
					continue;
			}

			/* cycle through the children and find any whose fd's are ready for reading */
			server_class_node* cur_node = router->server_class_list;
			while( cur_node != NULL ) {
				info_handler("searching child activity" );
				int cur_fd = cur_node->jabber->t_client->session->sock_obj->sock_fd;

				if( FD_ISSET(cur_fd, &listen_set) ) {
					++num_handled;
					FD_CLR(cur_fd,&listen_set);
					info_handler( "found active child %s", cur_node->server_class );

					cur_msg = client_recv( cur_node->jabber->t_client, 1 );
					info_handler( "%s received from %s", cur_node->server_class, cur_msg->sender );
					int handle_ret = server_class_handle_msg( router, cur_node, cur_msg );

					if( handle_ret == -1 ) {
						warning_handler( "server_class_handle_msg() returned -1" );
						cur_node = router->server_class_list; /*start over*/
						continue;

					} else if( handle_ret == 0 ) {
						/* delete and continue */
						warning_handler( "server_class_handle_msg() returned 0" );
						server_class_node* tmp_node = cur_node->next;
						remove_server_class( router, cur_node );	
						cur_node = tmp_node;
						continue;
					} 

					info_handler( "%s handled message successfully", cur_node->server_class );
					/* dont free message here */
					if( num_handled == select_ret ) 
						break;
				}
				if( num_handled == select_ret ) 
					break;
				cur_node = cur_node->next;

			} /* cycling through the server_class list */

		} /* no select errors */
	} 
}


/* determine where to route top level messages */
int router_registrar_handle_msg( transport_router_registrar* router_registrar, transport_message* msg ) {

	info_handler( "Received class: %s : command %s:  body: %s", msg->router_class, msg->router_command, msg->body );

	if( router_registrar == NULL || msg == NULL ) { return 0; }

	info_handler("Looking for server_class_node %s...",msg->router_class);
	server_class_node* active_class_node = find_server_class( router_registrar, msg->router_class );

	if( active_class_node == NULL ) { 
		info_handler("Could not find server_class_node %s, creating one.",msg->router_class);

		/* there is no server_class for msg->router_class so we build it here */
		if( strcmp( msg->router_command, "register") == 0 ) {

			info_handler("Adding server_class_node for %s",msg->router_class);
			active_class_node = 
				init_server_class( router_registrar, msg->sender, msg->router_class ); 

			if( active_class_node == NULL ) {
				fatal_handler( "router_listen(): active_class_node == NULL for %s", msg->sender );
				return 0;
			}

			if (router_registrar->server_class_list != NULL) {
				active_class_node->next = router_registrar->server_class_list;
				router_registrar->server_class_list->prev = active_class_node;
			}
			router_registrar->server_class_list = active_class_node;

			//spawn_server_class( (void*) active_class_node );

		} else {
			warning_handler( "router_register_handler_msg(): Bad Command [%s] for class [%s]",
				msg->router_command, msg->router_class );
		}

	} else if( strcmp( msg->router_command, "register") == 0 ) {
		/* there is a server_class for msg->router_class so we 
			need to either add a new server_node or update the existing one */

		
		server_node* s_node = find_server_node( active_class_node, msg->sender );

		if( s_node != NULL ) {
			s_node->available = 1;
			s_node->upd_time = time(NULL);
			info_handler( "Found matching registered server: %s. Updating.",
					s_node->remote_id );
		} else {
			s_node = init_server_node( msg->sender );

			info_handler( "Adding server_node for: %s.", s_node->remote_id );

			if (s_node == NULL ) {
				warning_handler( " Could not create new xerver_node for %s.",
					msg->sender );
				return 0;
			}

			s_node->next = active_class_node->current_server_node->next;
			s_node->prev = active_class_node->current_server_node;

			active_class_node->current_server_node->next->prev = s_node;
			active_class_node->current_server_node->next = s_node;
		}


	} else if( strcmp( msg->router_command, "unregister") == 0 ) {

		if( ! unregister_server_node( active_class_node, msg->sender ) )
			remove_server_class( router_registrar, active_class_node );

	} else {
		warning_handler( "router_register_handler_msg(): Bad Command [%s] for class [%s]",
			msg->router_command, msg->router_class );
	}

	return 1;
}


/* removes a server class node from the top level router_registrar */
int unregister_server_node( server_class_node* active_class_node, char* remote_id ) {

	server_node* d_node = find_server_node( active_class_node, remote_id );

	if ( d_node != NULL ) {

		info_handler( "Removing server_node for: %s.", d_node->remote_id );

		if ( d_node->next == NULL ) {
			warning_handler( "NEXT is NULL in ring [%s] -- "
				"THIS SHOULD NEVER HAPPEN",
				d_node->remote_id );

		}
		
		if ( d_node->prev == NULL ) {
			warning_handler( "PREV is NULL in a ring [%s] -- "
				"THIS SHOULD NEVER HAPPEN",
				d_node->remote_id );

		}

		if ( d_node->next == d_node && d_node->prev == d_node) {
			info_handler( "Last node, setting ring to NULL: %s.",
				d_node->remote_id );

			active_class_node->current_server_node = NULL;

			server_node_free( d_node );
			return 0;

		} else {
			info_handler( "Nodes remain, splicing: %s, %s",
				d_node->prev->remote_id,
				d_node->next->remote_id);

		info_handler( "d_node => %x, next => %x, prev => %x",
					d_node, d_node->next, d_node->prev );


			d_node->prev->next = d_node->next;
			d_node->next->prev = d_node->prev;

			info_handler( "prev => %x, prev->next => %x, prev->prev => %x",
				d_node->prev, d_node->prev->next, d_node->prev->prev );

			info_handler( "next => %x, next->next => %x, next->prev => %x",
				d_node->next, d_node->next->next, d_node->next->prev );
				
			if (active_class_node->current_server_node == d_node)
				active_class_node->current_server_node = d_node->next;


			server_node_free( d_node );
		}
	} 

	return 1;
}

server_node * find_server_node ( server_class_node * class, const char * remote_id ) {

	if ( class == NULL ) {
		warning_handler(" find_server_node(): bad arg!");
		return NULL;
	}

	server_node * start_node = class->current_server_node;
	server_node * node = class->current_server_node;

	do {
		if (node == NULL)
			return NULL;

		if ( strcmp(node->remote_id, remote_id) == 0 )
			return node;

		node = node->next;

	} while ( node != start_node );

	return NULL;
}

/* if we return -1, then we just deleted the server_class you were looking for
	if we return 0, then some other error has occured
	we return 1 otherwise */
int remove_server_class( transport_router_registrar* router, server_class_node* class ) {
	if( class == NULL )
		return 0;

	transport_message * msg = NULL;
	while ( (msg = client_recv(class->jabber->t_client, 0)) != NULL ) {
		server_class_handle_msg(router, class, msg);
		message_free(msg);
	}
	
	free( class->server_class );
	class->server_class = NULL;

	find_server_class( router, router_resource ); /* find deletes for us */

	if( router->server_class_list == NULL ) 
		return 0;
	return 1;
}

server_class_node * find_server_class ( transport_router_registrar * router, const char * class_id ) {

	if ( router == NULL ) {
		warning_handler(" find_server_class(): bad arg!");
		return NULL;
	}

	info_handler( "Finding server class for %s", class_id );
	server_class_node * class = router->server_class_list;
	server_class_node * dead_class = NULL;

	while ( class != NULL ) {

		if ( class->server_class == NULL ) {
			info_handler( "Found an empty server class" );

			if ( class->prev != NULL ) {
				class->prev->next = class->next;
				if( class->next != NULL ) {
					class->next->prev = class->prev;
				}

			} else {
				info_handler( "Empty class is the first on the list" );
				if( class->next != NULL ) 
					router->server_class_list = class->next;

				else { /* we're the last class node in the class node list */
					info_handler( "Empty class is the last on the list" );
					server_class_node_free( router->server_class_list );
					router->server_class_list = NULL;
					break;
				}
					
			}

			dead_class = class;
			class = class->next;

			info_handler( "Tossing our dead class" );
			server_class_node_free( dead_class );

			if ( class == NULL )
				return NULL;
		}

		if ( strcmp(class->server_class, class_id) == 0 )
			return class;
		info_handler( "%s != %s", class->server_class, class_id );

		class = class->next;
	}

	return NULL;
}

/* builds a new server class and connects to the jabber server with the new resource */
server_class_node* init_server_class( 
		transport_router_registrar* router, char* remote_id, char* server_class ) {

	size_t len = sizeof( server_class_node );
	server_class_node* node = (server_class_node*) safe_malloc( len );

	node->jabber = jabber_connect_init( router->jabber->server,
			router->jabber->port, router->jabber->username, 
			router->jabber->password, server_class, router->jabber->connect_timeout );



	node->server_class = strdup( server_class );
	if( server_class == NULL ) {
		fatal_handler( "imit_server_class(): out of memory for %s", server_class );
		return NULL;
	}

	info_handler( "Received class to init_server_class: %s", server_class );
	node->current_server_node = init_server_node( remote_id );
	if( node->current_server_node == NULL ) {
		fatal_handler( "init_server_class(): NULL server_node for %s", remote_id );
		return NULL;
	}


	if( ! j_connect( node->jabber ) ) {
		fatal_handler( "Unable to init server class %s", node->server_class );
		return NULL;
	}

	info_handler( "Jabber address in init for %s : address %x : username %s : resource %s", 
			node->server_class, node->jabber->t_client->session->sock_obj->sock_fd, 
			node->jabber->username,  node->jabber->resource );

	return node;

}

/* builds a new server_node to be added to the ring of server_nodes */
server_node* init_server_node(  char* remote_id ) {

	info_handler( "Initing server node for %s", remote_id );
	server_node* current_server_node;
	size_t size = sizeof( server_node);
	current_server_node = (server_node*) safe_malloc( size );

	current_server_node->remote_id = strdup(remote_id);
	if( current_server_node->remote_id == NULL ) {
		fatal_handler("init_server_class(): Out of Memory for %s", remote_id );
		return NULL;
	}
	
	current_server_node->reg_time = time(NULL);	
	current_server_node->available = 1;
	current_server_node->next = current_server_node;
	current_server_node->prev = current_server_node;


	return current_server_node;

}

int  server_class_handle_msg( transport_router_registrar* router, 
		server_class_node* s_node, transport_message* msg ) {

	if( s_node->current_server_node == NULL ) {
		/* return error to client ??!*/
		/* WE have no one to send the message to */
		warning_handler( "We no longer have any servers for %s : " 
				"no one to send the message to. Sending error message to %s", s_node->server_class, msg->sender );
		free( msg->recipient );  

		char* rec = strdup( msg->sender );
		if( rec == NULL ) {
			fatal_handler( "class msg_handler: out of memory");
			return 0;
		}

		info_handler( "Building error message to return for %s", s_node->server_class);
		msg->recipient = rec;
		set_msg_error(msg, "cancel", 501);

		client_send_message( s_node->jabber->t_client, msg );
		message_free( msg );

		remove_server_class( router, s_node );

		return -1;
	}

	info_handler( "[%s] Received from %s to \n%s", 
			s_node->server_class, msg->sender, msg->recipient );

	if( msg->is_error ) {
		warning_handler( "We've received an error message type: %s : code: %d", 
				msg->error_type, msg->error_code );

		if( strcmp( msg->error_type, "cancel" ) == 0 ) {
			warning_handler( "Looks like we've lost a server!" );
			server_node* dead_node = find_server_node( s_node, msg->sender );

			if( dead_node != NULL ) { 
				//message_free( msg );
				transport_message* tmp = dead_node->last_sent;

				/* copy over last sent, it will be freed in the unregister function */
				transport_message* tmp2 = message_init( tmp->body, tmp->subject, tmp->thread,
						tmp->recipient, tmp->sender );
					
				message_set_router_info( tmp2, tmp->router_from,  
						tmp->router_to, tmp->router_class, tmp->router_command, tmp->broadcast );

				if( ! unregister_server_node( s_node, dead_node->remote_id ) ) { 
					/* WE have no one to send the message to */
					warning_handler( "We no longer have any servers for %s : " 
							"no one to send the message to.", s_node->server_class );
					free( msg->recipient );  

					char* rec = strdup( msg->router_from );
					if( rec == NULL ) {
						fatal_handler( "class msg_handler: out of memory");
						return 0;
					}

					info_handler( "Building error message to return for %s", s_node->server_class);
					msg->recipient = rec;
					client_send_message( s_node->jabber->t_client, msg );
					message_free( tmp2 );
					message_free( msg );
					return 0;

				} else {
					msg = tmp2;
				}
			}
		}
	} 


	server_node* c_node = s_node->current_server_node->next;

	/* not implemented yet */
	while( ! c_node->available ) {
		if( c_node == s_node->current_server_node ) {
			warning_handler("No server_node's are available for %s", s_node->server_class );
			/* XXX send error message to client */
			return 0;
		}
		c_node = c_node->next;
	}
	s_node->current_server_node = c_node;

	transport_message * new_msg =
		message_init(	msg->body, msg->subject, msg->thread, 
				s_node->current_server_node->remote_id, msg->sender );

	message_set_router_info( new_msg, msg->sender, NULL, NULL, NULL, 0 );

	info_handler( "[%s] Routing message from [%s]\nto [%s]", s_node->server_class, msg->sender, new_msg->recipient );
	info_handler( "New Message Details: sender:%s recipient: %s", new_msg->sender, new_msg->recipient );

	message_free( s_node->current_server_node->last_sent );
	s_node->current_server_node->last_sent = msg;

	if ( new_msg != NULL && client_send_message( s_node->jabber->t_client, new_msg ) ) {
		s_node->current_server_node->serve_count++;
		s_node->current_server_node->la_time = time(NULL);
		message_free( new_msg ); // XXX
		return 1;
	}
	info_handler( "message sent" );
	message_free( new_msg ); // XXX

	return 0;
}

int router_registrar_free( transport_router_registrar* router_registrar ) {
	if( router_registrar == NULL ) return 0;
	jabber_connect_free( router_registrar->jabber );

	/* free the server_class list XXX */
	while( router_registrar->server_class_list != NULL ) {
		remove_server_class(router_registrar, router_registrar->server_class_list);
	}

	free( router_registrar );



	return 1;
}


int server_class_node_free( server_class_node* node ) {
	if( node == NULL ) { return 0; }
	if( node->server_class != NULL ) 
		free( node->server_class );

	jabber_connect_free( node->jabber );

	/* just in case, free the list */
	while( node->current_server_node != NULL ) {
		unregister_server_node( node, node->current_server_node->remote_id );
	}
	free( node );
	return 1;
}

int server_node_free( server_node* node ) {
	if( node == NULL ) { return 0; }
	message_free( node->last_sent );
	free( node->remote_id );
	free( node );
	return 1;
}

int jabber_connect_free( jabber_connect* jabber ) {
	if( jabber == NULL ) { return 0; }
	client_free( jabber->t_client );
	free( jabber->username );
	free( jabber->password );
	free( jabber->resource );
	free( jabber->server );
	free( jabber );
	return 1;
}


