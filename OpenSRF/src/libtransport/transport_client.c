#include "opensrf/transport_client.h"


//int main( int argc, char** argv );

/*
int main( int argc, char** argv ) {

	transport_message* recv;
	transport_message* send;

	transport_client* client = client_init( "spacely.georgialibraries.org", 5222 );

	// try to connect, allow 15 second connect timeout 
	if( client_connect( client, "admin", "asdfjkjk", "system", 15 ) ) {
		printf("Connected...\n");
	} else { 
		printf( "NOT Connected...\n" ); exit(99); 
	}

	while( (recv = client_recv( client, -1 )) ) {

		if( recv->body ) {
			int len = strlen(recv->body);
			char buf[len + 20];
			memset( buf, 0, len + 20); 
			sprintf( buf, "Echoing...%s", recv->body );
			send = message_init( buf, "Echoing Stuff", "12345", recv->sender, "" );
		} else {
			send = message_init( " * ECHOING * ", "Echoing Stuff", "12345", recv->sender, "" );
		}

		if( send == NULL ) { printf("something's wrong"); }
		client_send_message( client, send );
				
		message_free( send );
		message_free( recv );
	}

	printf( "ended recv loop\n" );

	return 0;

}
*/


transport_client* client_init( char* server, int port, int component ) {

	if(server == NULL) return NULL;

	/* build and clear the client object */
	size_t c_size = sizeof( transport_client);
	transport_client* client = (transport_client*) safe_malloc( c_size );

	/* build and clear the message list */
	size_t l_size = sizeof( transport_message_list );
	client->m_list = (transport_message_list*) safe_malloc( l_size );

	client->m_list->type = MESSAGE_LIST_HEAD;
	client->session = init_transport( server, port, client, component );


	if(client->session == NULL) {
		fatal_handler( "client_init(): Out of Memory"); 
		return NULL;
	}
	client->session->message_callback = client_message_handler;

	return client;
}

int client_connect( transport_client* client, 
		char* username, char* password, char* resource, 
		int connect_timeout, enum TRANSPORT_AUTH_TYPE  auth_type ) {
	if(client == NULL) return 0; 
	return session_connect( client->session, username, 
			password, resource, connect_timeout, auth_type );
}

int client_disconnect( transport_client* client ) {
	if( client == NULL ) { return 0; }
	return session_disconnect( client->session );
}

int client_connected( transport_client* client ) {
	if(client == NULL) return 0;
	return client->session->state_machine->connected;
}

int client_send_message( transport_client* client, transport_message* msg ) {
	if(client == NULL) return 0;
	return session_send_msg( client->session, msg );
}


transport_message* client_recv( transport_client* client, int timeout ) {
	if( client == NULL ) { return NULL; }

	transport_message_node* node;
	transport_message* msg;


	/* see if there are any message in the messages queue */
	if( client->m_list->next != NULL ) {
		/* pop off the first one... */
		node = client->m_list->next;
		client->m_list->next = node->next;
		msg = node->message;
		free( node );
		return msg;
	}

	if( timeout == -1 ) {  /* wait potentially forever for data to arrive */

		while( client->m_list->next == NULL ) {
			if( ! session_wait( client->session, -1 ) ) {
				return NULL;
			}
		}

	} else { /* wait at most timeout seconds */

	
		/* if not, loop up to 'timeout' seconds waiting for data to arrive */
		time_t start = time(NULL);	
		time_t remaining = (time_t) timeout;

		int counter = 0;

		int wait_ret;
		while( client->m_list->next == NULL && remaining >= 0 ) {

			if( ! (wait_ret= session_wait( client->session, remaining)) ) 
				return NULL;

			++counter;

#ifdef _ROUTER
			// session_wait returns -1 if there is no more data and we're a router
			if( remaining == 0 && wait_ret == -1 ) {
				break;
			}
#else
			if( remaining == 0 ) // or infinite loop
				break;
#endif

			remaining -= (int) (time(NULL) - start);
		}

	}

	/* again, see if there are any messages in the message queue */
	if( client->m_list->next != NULL ) {
		/* pop off the first one... */
		node = client->m_list->next;
		client->m_list->next = node->next;
		msg = node->message;
		free( node );
		return msg;
	} else {
		return NULL;
	}
}

/* throw the message into the message queue */
void client_message_handler( void* client, transport_message* msg ){

	if(client == NULL) return;
	if(msg == NULL) return; 

	transport_client* cli = (transport_client*) client;

	size_t len = sizeof(transport_message_node);
	transport_message_node* node = 
		(transport_message_node*) safe_malloc(len);
	node->type = MESSAGE_LIST_ITEM;
	node->message = msg;


	/* find the last node and put this onto the end */
	transport_message_node* tail = cli->m_list;
	transport_message_node* current = tail->next;

	while( current != NULL ) {
		tail = current;
		current = current->next;
	}
	tail->next = node;
}


int client_free( transport_client* client ){
	if(client == NULL) return 0; 

	session_free( client->session );
	transport_message_node* current = client->m_list->next;
	transport_message_node* next;

	/* deallocate the list of messages */
	while( current != NULL ) {
		next = current->next;
		message_free( current->message );
		free(current);
		current = next;
	}

	free( client->m_list );
	free( client );
	return 1;
}

