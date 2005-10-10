/*
Copyright (C) 2005  Georgia Public Library Service 
Bill Erickson <billserickson@gmail.com>

This program is free software; you can redistribute it and/or
modify it under the terms of the GNU General Public License
as published by the Free Software Foundation; either version 2
of the License, or (at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.
*/

#include "osrf_chat.h"
#include <string.h>
#include <stdio.h>

int __osrfChatXMLErrorOcurred = 0;
int __osrfChatClientSentDisconnect = 0;

/* shorter version of strcmp */
static int eq(const char* a, const char* b) { return (a && b && !strcmp(a,b)); }

/* gnarly debug function */
static void chatdbg( osrfChatServer* server ) {

	if(!server) return;

	growing_buffer* buf = buffer_init(256);

	buffer_add(buf, "---------------------------------------------------------------------\n");

	buffer_fadd(buf, 
		"ChopChop Debug:\n"
		"Connections:           %lu\n"
		"Named nodes in hash:   %lu\n"
		"Domain:                %s\n"
		"Port:                  %d\n"
		"S2S Port:              %d\n"
		"-------------------------------------------------------\n",
		osrfListGetCount(server->nodeList), osrfHashGetCount(server->nodeHash),
		server->domain, server->port, server->s2sport );

	osrfListIterator* itr = osrfNewListIterator(server->nodeList);
	osrfChatNode* node;

	while( (node = osrfListIteratorNext(itr)) ) {

		buffer_fadd( buf, 
			"sockid:    %d\n"
			"Remote:    %s\n"
			"State:     %d\n"
			"XMLState:  %d\n"
			"In Parse:  %d\n"
			"to:        %s\n"
			"Resource:  %s\n"
			"Username:  %s\n"
			"Domain:    %s\n"
			"Authkey:   %s\n"
			"type:		%d\n"
			"-------------------------------------------------------\n",
			node->sockid, node->remote, node->state, node->xmlstate, node->inparse,
			node->to, node->resource, node->username, node->domain, node->authkey, node->type );
	}

	debug_handler("DEBUG:\n%s", buf->buf );
	buffer_free(buf);
	osrfListIteratorFree(itr);
}

osrfChatServer* osrfNewChatServer( char* domain, char* secret, int s2sport ) {
	if(!(domain && secret)) return NULL;

	osrfChatServer* server = safe_malloc(sizeof(osrfChatServer));

	server->nodeHash = osrfNewHash();
	server->nodeList = osrfNewList();
	server->deadNodes = osrfNewList();
	server->nodeList->freeItem = &osrfChatNodeFree;
	server->domain = strdup(domain);
	server->s2sport = s2sport;

	server->mgr = safe_malloc(sizeof(socket_manager));
	server->mgr->data_received = &osrfChatHandleData;
	server->mgr->blob = server;
	server->mgr->on_socket_closed = &osrfChatSocketClosed;

	if(secret) server->secret = strdup(secret);
	return server;
}

void osrfChatCleanupClients( osrfChatServer* server ) {
	if(server) {
		osrfListFree(server->deadNodes);
		server->deadNodes = osrfNewList();
	}
}



osrfChatNode* osrfNewChatNode( int sockid, char* domain ) {
	if(sockid < 1 || !domain) return NULL;
	osrfChatNode* node	= safe_malloc(sizeof(osrfChatNode));
	node->state				= OSRF_CHAT_STATE_NONE;
	node->msgs				= NULL; /* only s2s nodes cache messages */
	node->parserCtx		= xmlCreatePushParserCtxt(osrfChatSaxHandler, node, "", 0, NULL);
	node->msgDoc			= xmlNewDoc(BAD_CAST "1.0");
	node->domain = strdup(domain);
	xmlKeepBlanksDefault(0);
	node->authkey			= NULL;
	node->username			= NULL;
	node->resource			= NULL;
	node->to					= NULL;
	node->type = 0;
	return node;
}


osrfChatNode* osrfNewChatS2SNode( char* domain, char* remote ) {
	if(!(domain && remote)) return NULL;
	osrfChatNode* n = osrfNewChatNode( 1, domain );
	n->state		= OSRF_CHAT_STATE_S2S_CHALLENGE;
	n->sockid	= -1;
	n->remote	= strdup(remote);
	n->msgs		= osrfNewList();
	n->msgs->freeItem = &osrfChatS2SMessageFree;
	n->type = 1;
	return n;
}

void osrfChatS2SMessageFree(void* n) { free(n); }

void osrfChatNodeFree( void* node ) {
	if(!node) return;
	osrfChatNode* n = (osrfChatNode*) node;

	/* we can't free messages that are mid-parse because the
		we can't free the parser context */
	if(n->inparse) {
		n->inparse = 0;
		osrfListPush(n->parent->deadNodes, n);
		return;
	}

	free(n->remote);
	free(n->to);
	free(n->username);
	free(n->resource);
	free(n->domain);
	free(n->authkey);

	osrfListFree(n->msgs);

	if(n->parserCtx) {
		xmlFreeDoc(n->parserCtx->myDoc);
		xmlFreeParserCtxt(n->parserCtx);
	}

	xmlFreeDoc(n->msgDoc);
	free(n);
}



int osrfChatServerConnect( osrfChatServer* cs,  int port, int s2sport, char* listenAddr ) {
	if(!(cs && port && listenAddr)) return -1;
	cs->port = port;
	cs->s2sport = s2sport;
	if( socket_open_tcp_server(cs->mgr, port, listenAddr ) < 0 )
		return -1;
	if( socket_open_tcp_server(cs->mgr, s2sport, listenAddr ) < 0 )
		return -1;
	return 0;
}


int osrfChatServerWait( osrfChatServer* server ) {
	if(!server) return -1;
	while(1) {
		if(socket_wait_all(server->mgr, -1) < 0)
			warning_handler( "jserver_wait(): socket_wait_all() returned error");
	}
	return -1;
}


void osrfChatServerFree(osrfChatServer* server ) {
	if(!server) return;
	osrfHashFree(server->nodeHash);
	osrfListFree(server->nodeList);
	free(server->mgr);
	free(server->secret);
}


void osrfChatHandleData( void* cs, 
	socket_manager* mgr, int sockid, char* data, int parent_id ) {

	if(!(cs && mgr && sockid && data)) return;

	osrfChatServer* server = (osrfChatServer*) cs;

	osrfChatNode* node = osrfListGetIndex( server->nodeList, sockid );

	if(!node) {
		debug_handler("Adding new connection for sockid %d", sockid );
		node = osrfChatAddNode( server, sockid );
	}

	if(node) {
		if( (osrfChatPushData( server, node, data ) == -1) ) {
			warning_handler("Node at socket %d received bad XML, disconnecting...", sockid );
			osrfChatSendRaw(  node, OSRF_CHAT_PARSE_ERROR );
			osrfChatRemoveNode( server, node );
		}
	}

	osrfChatCleanupClients(server); /* clean up old dead clients */
}


void osrfChatSocketClosed( void* blob, int sockid ) {
	if(!blob) return;
	osrfChatServer* server = (osrfChatServer*) blob;
	osrfChatNode* node = osrfListGetIndex(server->nodeList, sockid);
	osrfChatRemoveNode( server, node );
}

osrfChatNode* osrfChatAddNode( osrfChatServer* server, int sockid ) {
	if(!(server && sockid)) return NULL;
	osrfChatNode* node = osrfNewChatNode(sockid, server->domain);
	node->parent = server;
	node->sockid = sockid;
	osrfListSet( server->nodeList, node, sockid );
	return node;
}

void osrfChatRemoveNode( osrfChatServer* server, osrfChatNode* node ) {
	if(!(server && node)) return;
	socket_disconnect(server->mgr, node->sockid);
	if(node->remote) 
		osrfHashRemove( server->nodeHash, node->remote );
	osrfListRemove( server->nodeList, node->sockid ); /* this will free it */
}

int osrfChatSendRaw( osrfChatNode* node, char* msgXML ) {
	if(!(node && msgXML)) return -1;
	return socket_send( node->sockid, msgXML );
}




void osrfChatNodeFinish( osrfChatServer* server, osrfChatNode* node ) {
	if(!(server && node)) return;
	osrfChatSendRaw( node, "</stream:stream>");
	osrfChatRemoveNode( server, node );
}


int osrfChatSend( osrfChatServer* cs, osrfChatNode* node, char* toAddr, char* fromAddr, char* msgXML ) {
	if(!(cs && node && toAddr && msgXML)) return -1;

	int l = strlen(toAddr);
	char dombuf[l];
	bzero(dombuf, l);
	jid_get_domain( toAddr, dombuf );	

	if( eq( dombuf, cs->domain ) ) { /* this is to a user we host */

		osrfChatNode* tonode = osrfHashGet(cs->nodeHash, toAddr);
		if(tonode) {
			osrfChatSendRaw( tonode, msgXML );

		} else {

			/* send an error message saying we don't have this connection */
			warning_handler("We have no connection for %s", toAddr);
			char* xml = va_list_to_string( OSRF_CHAT_NO_RECIPIENT, toAddr, fromAddr );
			osrfChatSendRaw( node, xml );
			free(xml);
		}

	} else {

		osrfChatNode* tonode = osrfHashGet(cs->nodeHash, dombuf);
		if(tonode) {
			if( tonode->state == OSRF_CHAT_STATE_CONNECTED ) {
				debug_handler("Routing message to server %s", dombuf);
				osrfChatSendRaw( tonode, msgXML );

			} else {
				info_handler("Received s2s message and we're still trying to connect...caching");
				osrfListPush( tonode->msgs, strdup(msgXML) );
			}

		} else {

			if( osrfChatInitS2S( cs, dombuf, toAddr, msgXML ) != 0 ) {
				warning_handler("We are unable to connect to remote server %s for recipient %s", dombuf, toAddr);
				char* xml = va_list_to_string( OSRF_CHAT_NO_RECIPIENT, toAddr, fromAddr );
				osrfChatSendRaw( node, xml );
				free(xml);
			}
		}
	}

	return 0;
}


/*
void osrfChatCacheS2SMessage( char* toAddr, char* msgXML, osrfChatNode* snode ) {
	if(!(toAddr && msgXML)) return;
	osrfChatS2SMessage* msg = safe_malloc(sizeof(osrfChatS2SMessage));
	msg->toAddr = strdup(toAddr);
	msg->msgXML = strdup(msgXML);
	info_handler("Pushing client message onto s2s queue waiting for connect... ");
	osrfListPush( snode->msgs, msgXML );
}
*/


int osrfChatInitS2S( osrfChatServer* cs, char* remote, char* toAddr, char* msgXML ) {
	if(!(cs && remote && toAddr && msgXML)) return -1;

	info_handler("Initing server2server connection to domain %s", remote );
	osrfChatNode* snode = osrfNewChatS2SNode( cs->domain, remote );
	snode->parent = cs;

	/* try to connect to the remote site */
	snode->sockid = socket_open_tcp_client(cs->mgr, cs->s2sport, remote);
	if(snode->sockid < 1) {
		warning_handler("Unable to connect to remote server at %s", remote );
		return -1;
	}

	/* store the message we were supposed to deliver until we're fully connected */
	//osrfChatCacheS2SMessage( toAddr, msgXML, snode );
	osrfListPush( snode->msgs, strdup(msgXML) );
	osrfHashSet(cs->nodeHash, snode, remote );
	osrfListSet(cs->nodeList, snode, snode->sockid );

	/* send the initial s2s request */
	osrfChatSendRaw( snode, OSRF_CHAT_S2S_INIT );

	debug_handler("Added new s2s node...");
	chatdbg(cs);

	return 0;
}


/* commence SAX handling code */

int osrfChatPushData( osrfChatServer* server, osrfChatNode* node, char* data ) {
	if(!(node && data)) return -1;

	chatdbg(server);

	debug_handler("pushing data into xml parser for node %d:\n%s", node->sockid, data);
	node->inparse = 1;
	xmlParseChunk(node->parserCtx, data, strlen(data), 0);
	node->inparse = 0;

	if(__osrfChatXMLErrorOcurred) {
		__osrfChatXMLErrorOcurred = 0;
		return -1;
	}

	/* we can't do cleanup of the XML handlers while in the middle of a 
		data push, so set flags in the data push and doe the cleanup here */
	/*
	if(__osrfChatClientSentDisconnect) {
		__osrfChatClientSentDisconnect  = 0;
		osrfChatNodeFinish( server, node );
	}
	*/

	return 0;
}


void osrfChatStartStream( void* blob ) {
	debug_handler("Starting new client stream...");
}


void osrfChatStartElement( void* blob, const xmlChar *name, const xmlChar **atts ) {
	if(!(blob && name)) return;
	osrfChatNode* node = (osrfChatNode*) blob;

	int status = -1;
	char* nm = (char*) name;

	debug_handler("Starting element %s with namespace %s", nm, xmlSaxAttr(atts, "xmlns") );

	switch( node->state ) {

		case OSRF_CHAT_STATE_NONE:
			status = osrfChatHandleNewConnection( node, nm, atts );
			break;

		case OSRF_CHAT_STATE_CONNECTING:
			status = osrfChatHandleConnecting( node, nm, atts );
			break;

		case OSRF_CHAT_STATE_CONNECTED:
			status = osrfChatHandleConnected( node, nm, atts );
			break;

		case OSRF_CHAT_STATE_S2S_CHALLENGE:	 
			status = osrfChatHandleS2SChallenge( node, nm, atts );
			break;

		case OSRF_CHAT_STATE_S2S_RESPONSE: /* server waiting for client response to challenge */
			if(eq(nm, "db:result")) {
				char* remote = xmlSaxAttr(atts, "from");
				if(remote) node->remote = strdup(remote); /* copy off the client's id */
				status = 0;
				node->xmlstate |= OSRF_CHAT_STATE_INS2SRESULT;
			} else status = -1; 
			break;

		case OSRF_CHAT_STATE_S2S_VERIFY:	/* client : waiting for server verify message */
			if(eq(nm, "db:verify")) {
				char* id = xmlSaxAttr( atts, "id" );
				if(id) {
					char* xml = va_list_to_string( OSRF_CHAT_S2S_VERIFY_RESPONSE, 
							node->remote, node->domain, id );
					osrfChatSendRaw( node, xml );
					free(xml);
					node->state = OSRF_CHAT_STATE_S2S_VERIFY_FINAL;
					status = 0;
				}
			}
			break;

		case OSRF_CHAT_STATE_S2S_VERIFY_RESPONSE:	/* server waiting for client verify response */
		case OSRF_CHAT_STATE_S2S_VERIFY_FINAL: /* client waitig for final verify */
			status = osrfChatHandleS2SConnected( node, nm, atts );
			break;

	}

	if(status != 0) 
		osrfChatParseError( node, "We don't know how to handle the XML data received" );
}

#define CHAT_CHECK_VARS(x,y,z) if(!(x && y)) return -1; if(z) debug_handler(z);



int osrfChatHandleS2SConnected( osrfChatNode* node, const char* name, const xmlChar**atts ) {
	CHAT_CHECK_VARS(node, name, "osrfChatHandleS2SConnected" );

	int status = -1;

	if(eq(name,"db:verify")) { /* server receives verify from client */
		char* xml = va_list_to_string(OSRF_CHAT_S2S_VERIFY_FINAL, node->domain, node->remote ); 
		osrfChatSendRaw(node, xml );
		free(xml);
		status = 0;
	}

	if(eq(name, "db:result")) {
		/* send all the messages that we have queued for this server */
		node->state = OSRF_CHAT_STATE_CONNECTED;
		osrfListIterator* itr = osrfNewListIterator(node->msgs);

		char* xml;
		while( (xml = (char*) osrfListIteratorNext(itr)) ) {
			xmlDocPtr doc = xmlParseMemory(xml, strlen(xml));
			if(doc) {
				char* from = (char*) xmlGetProp(xmlDocGetRootElement(doc), BAD_CAST "from");
				char* to = (char*) xmlGetProp(xmlDocGetRootElement(doc), BAD_CAST "to");
				osrfChatSend( node->parent, node, to, from, xml );
				debug_handler("Sending cached message from %s to %s", from, to);
				xmlFree(to); xmlFree(from);
				xmlFreeDoc(doc);
			}
		}

		osrfListIteratorFree(itr);
		osrfListFree(node->msgs);
		node->msgs = NULL;
		status = 0;
	}

	if(status == 0) {
		info_handler("Successfully made S2S connection to %s", node->remote );
		node->state = OSRF_CHAT_STATE_CONNECTED;
		node->xmlstate = 0;
	}

	return status;
}


/** check the namespace of the stream message to see if it's a server or client connection */
int osrfChatHandleNewConnection( osrfChatNode* node, const char* name, const xmlChar** atts ) {
	CHAT_CHECK_VARS(node, name, "osrfChatHandleNewConnection()");

	if(!eq(name, "stream:stream")) return -1;

	node->authkey = osrfChatMkAuthKey();
	char* ns = xmlSaxAttr(atts, "xmlns");
	if(!ns) return -1;

	if(eq(ns, "jabber:client")) { /* client connection */

		char* domain = xmlSaxAttr( atts, "to" );
		if(!domain) return -1; 
	
		if(!eq(domain, node->domain)) {
			warning_handler("Client attempting to connect to invalid domain");
			return -1;
		}
	
		char* buf = va_list_to_string( OSRF_CHAT_START_STREAM, domain, node->authkey );
		node->state = OSRF_CHAT_STATE_CONNECTING;
	
		debug_handler("Server responding to connect message with\n%s\n", buf );
		osrfChatSendRaw( node, buf );
		free(buf);
		return 0;
	}

	/* server to server init */
	if(eq(ns, "jabber:server")) { /* client connection */
		info_handler("We received a new server 2 server connection, generating auth key...");
		char* xml = va_list_to_string( OSRF_CHAT_S2S_CHALLENGE, node->authkey );
		osrfChatSendRaw( node, xml );
		free(xml);
		node->state = OSRF_CHAT_STATE_S2S_RESPONSE; /* the next message should be the response */
		node->type = 1;
		return 0;
	}

	return -1;
}



char* osrfChatMkAuthKey() {
	char keybuf[112];
	bzero(keybuf, 112);
	snprintf(keybuf, 111, "%d%d%s", (int) time(NULL), getpid(), getenv("HOSTNAME"));
	return strdup(shahash(keybuf));
}

int osrfChatHandleConnecting( osrfChatNode* node, const char* name, const xmlChar** atts ) {
	CHAT_CHECK_VARS(node, name, "osrfChatHandleConnecting()");
	debug_handler("Handling connect node %s", name );

	if(eq(name, "iq")) node->xmlstate |= OSRF_CHAT_STATE_INIQ;
	else if(eq(name,"username")) node->xmlstate |= OSRF_CHAT_STATE_INUSERNAME;
	else if(eq(name,"resource")) node->xmlstate |= OSRF_CHAT_STATE_INRESOURCE;
	return 0;
}

int osrfChatHandleConnected( osrfChatNode* node, const char* name, const xmlChar** atts ) {
	CHAT_CHECK_VARS(node, name, "osrfChatHandleConnected()");

	if(eq(name,"message")) {

		/* drop the old message and start with a new one */
		xmlNodePtr root = xmlNewNode(NULL, name);
		xmlAddAttrs(root, atts);
		xmlNodePtr oldRoot = xmlDocSetRootElement(node->msgDoc, root);
		free(node->to);

		char* to = xmlSaxAttr(atts, "to");
		if(!to) to = "";

		node->to = strdup(to);
		if(oldRoot) xmlFreeNode(oldRoot);
		node->xmlstate = OSRF_CHAT_STATE_INMESSAGE;

	} else {

		/* all non "message" nodes are simply added to the message */
		xmlNodePtr nodep = xmlNewNode(NULL, name);
		xmlAddAttrs(nodep, atts);
		xmlAddChild(xmlDocGetRootElement(node->msgDoc), nodep);
	}

	return 0;
}

/* takes s2s secret, hashdomain, and the s2s auth token */
static char* osrfChatGenerateS2SKey( char* secret, char* hashdomain, char* authtoken ) {
	if(!(secret && hashdomain && authtoken)) return NULL;
	info_handler("Generating s2s key with auth token: %s", authtoken );
	char* a = shahash(secret);
	debug_handler("S2S secret hash: %s", a);
	char* b = va_list_to_string("%s%s", a, hashdomain);
	char* c = shahash(b);
	debug_handler("S2S intermediate hash: %s", c);
	char* d = va_list_to_string("%s%s", c, authtoken);
	char* e = strdup(shahash(d));
	free(b); free(d); 
	return e;
}

int osrfChatHandleS2SChallenge( osrfChatNode* node, const char* name, const xmlChar** atts ) {
	CHAT_CHECK_VARS(node, name, "osrfChatHandleS2SChallenge()");

/* here we respond to the stream challenge */
	if(eq(name, "stream:stream")) {
		char* id = xmlSaxAttr(atts, "id");
		if(id) {
			/* we use our domain in the s2s challenge hash */
			char* d = osrfChatGenerateS2SKey(node->parent->secret, node->domain, id );
			char* e = va_list_to_string(OSRF_CHAT_S2S_RESPONSE, node->remote, node->domain, d );
			info_handler("Answering s2s challenge with key:  %s", e );
			osrfChatSendRaw( node, e );
			free(d); free(e);
			node->state = OSRF_CHAT_STATE_S2S_VERIFY;
			return 0;
		}
	}

	return -1;
}

/*
int osrfChatHandleS2SResponse( osrfChatNode* node, const char* name, const xmlChar** atts ) {
	CHAT_CHECK_VARS(node, name, "osrfChatHandleS2SResponse()");

	if(eq(name, "db:result")) {
		node->xmlstate |= OSRF_CHAT_STATE_INS2SRESULT;
		return 0;
	}

	return -1;
}
*/



void osrfChatEndElement( void* blob, const xmlChar* name ) {
	if(!(blob && name)) return;
	osrfChatNode* node = (osrfChatNode*) blob;

	char* nm = (char*) name;

	if(eq(nm,"stream:stream")) {
		osrfChatNodeFinish( node->parent, node );
		return;
	}

	if( node->state == OSRF_CHAT_STATE_CONNECTED ) {
		if(eq(nm, "message")) {

			xmlNodePtr msg = xmlDocGetRootElement(node->msgDoc);
			if(msg && node->type == 0)
				xmlSetProp(msg, BAD_CAST "from", BAD_CAST node->remote );
			char* string = xmlDocToString(node->msgDoc, 0 );

			char* from = (char*) xmlGetProp(msg, BAD_CAST "from");
			debug_handler( "Routing message to %s\n%s\n", node->to, from, string );
			osrfChatSend( node->parent, node, node->to, from, string ); 
			xmlFree(from);
			free(string);
		}
	}

	if( node->state == OSRF_CHAT_STATE_CONNECTING ) {
		if( node->xmlstate & OSRF_CHAT_STATE_INIQ ) {

			if(eq(nm, "iq")) {
				node->xmlstate &= ~OSRF_CHAT_STATE_INIQ;
				node->remote = va_list_to_string( 
						"%s@%s/%s", node->username, node->domain, node->resource );

				debug_handler("Setting remote address to %s", node->remote );
				osrfChatSendRaw( node, OSRF_CHAT_LOGIN_OK );
				osrfHashSet( node->parent->nodeHash, node, node->remote );
				node->state = OSRF_CHAT_STATE_CONNECTED;
			}
		}
	}
}


void osrfChatHandleCharacter( void* blob, const xmlChar *ch, int len) {
	if(!(blob && ch && len)) return;
	osrfChatNode* node = (osrfChatNode*) blob;

	/*
	debug_handler("Char Handler: state %d, xmlstate %d, chardata %s", 
			node->state, node->xmlstate, (char*) ch );
			*/

	if( node->state == OSRF_CHAT_STATE_CONNECTING ) {
		if( node->xmlstate & OSRF_CHAT_STATE_INIQ ) {

			if( node->xmlstate & OSRF_CHAT_STATE_INUSERNAME ) {
				free(node->username);
				node->username = strndup((char*) ch, len);
				node->xmlstate &= ~OSRF_CHAT_STATE_INUSERNAME;
			}

			if( node->xmlstate & OSRF_CHAT_STATE_INRESOURCE ) {
				free(node->resource);
				node->resource = strndup((char*) ch, len);
				node->xmlstate &= ~OSRF_CHAT_STATE_INRESOURCE;
			}
		}

		return;
	} 
	
	if( node->state == OSRF_CHAT_STATE_CONNECTED ) {
		xmlNodePtr last = xmlGetLastChild(xmlDocGetRootElement(node->msgDoc));
		xmlNodePtr txt = xmlNewTextLen(ch, len);
		xmlAddChild(last, txt);
		return;
	}

	if( node->state == OSRF_CHAT_STATE_S2S_RESPONSE &&
			(node->xmlstate & OSRF_CHAT_STATE_INS2SRESULT) ) {

		char* key = strndup((char*) ch, len);
		debug_handler("Got s2s key from %s : %s", node->remote, key );
		char* e = osrfChatGenerateS2SKey(node->parent->secret, node->remote, node->authkey );
		info_handler("\nReceived s2s key from server: %s\nKey should be: %s", key, e );

		if(eq(key, e)) {
			char* msg = va_list_to_string(OSRF_CHAT_S2S_VERIFY_REQUEST,  
					node->authkey, node->domain, node->remote, e );
			osrfChatSendRaw(node, msg );
			free(msg);
			node->state = OSRF_CHAT_STATE_S2S_VERIFY_RESPONSE;
			node->xmlstate = 0;

		} else {
			warning_handler("Server2Server keys do not match!");
		}

		/* do the hash dance again */
	}

}


void osrfChatParseError( void* blob, const char* msg, ... ) {

	__osrfChatXMLErrorOcurred = 1;
}




