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

#ifndef OSRF_CHAT_H
#define OSRF_CHAT_H


/* opensrf headers */
#include "opensrf/utils.h"
#include "opensrf/osrf_hash.h"
#include "opensrf/osrf_list.h"
#include "opensrf/log.h"
#include "opensrf/xml_utils.h"
#include "opensrf/socket_bundle.h"
#include "opensrf/sha.h"
#include "opensrf/transport_message.h"

/* libxml2 headers */
#include <libxml/parser.h>
#include <libxml/tree.h>
#include <libxml/globals.h>
#include <libxml/xmlerror.h>

/* client to server XML */
#define OSRF_CHAT_START_STREAM "<?xml version='1.0'?><stream:stream "\
	"xmlns:stream='http://etherx.jabber.org/streams' xmlns='jabber:client' "\
	"from='%s' version='1.0' id='%s'>" 

#define OSRF_CHAT_PARSE_ERROR "<stream:stream xmlns:stream='http://etherx.jabber.org/streams' "\
	"version='1.0'><stream:error xmlns:stream='http://etherx.jabber.org/streams'>"\
	"<xml-not-well-formed xmlns='urn:ietf:params:xml:ns:xmpp-streams'/>"	\
	"<text xmlns='urn:ietf:params:xml:ns:xmpp-streams'>syntax error</text></stream:error></stream:stream>" 

#define OSRF_CHAT_LOGIN_OK "<iq xmlns='jabber:client' id='0123456789' type='result'/>"

#define OSRF_CHAT_NO_RECIPIENT "<message xmlns='jabber:client' type='error' from='%s' to='%s'>"\
	"<error type='cancel' code='404'><item-not-found xmlns='urn:ietf:params:xml:ns:xmpp-stanzas'/>"\
	"</error><body>NOT ADDING BODY</body></message>"

/* ---------------------------------------------------------------------------------- */
/* server to server XML */

// client to server init
#define OSRF_CHAT_S2S_INIT "<stream:stream xmlns:stream='http://etherx.jabber.org/streams' "\
	"xmlns='jabber:server' xmlns:db='jabber:server:dialback'>"

// server to client challenge 
#define OSRF_CHAT_S2S_CHALLENGE "<stream:stream xmlns:stream='http://etherx.jabber.org/streams' "\
	"xmlns='jabber:server' id='%s' xmlns:db='jabber:server:dialback'>"

// client to server challenge response
#define OSRF_CHAT_S2S_RESPONSE "<db:result xmlns:db='jabber:server:dialback' to='%s' from='%s'>%s</db:result>"

// server to client verify
#define OSRF_CHAT_S2S_VERIFY_REQUEST "<db:verify xmlns:db='jabber:server:dialback' id='%s' from='%s' to='%s'>%s</db:verify>"

// client to server verify response
#define OSRF_CHAT_S2S_VERIFY_RESPONSE "<db:verify xmlns:db='jabber:server:dialback' type='valid' to='%s' from='%s' id='%s'/>"

//server to client final verification
#define OSRF_CHAT_S2S_VERIFY_FINAL "<db:result xmlns:db='jabber:server:dialback' type='valid' from='%s' to ='%s'/>"


/* c2s states */
#define OSRF_CHAT_STATE_NONE						0		/* blank node */
#define OSRF_CHAT_STATE_CONNECTING				1		/* we have received the opening stream */
#define OSRF_CHAT_STATE_CONNECTED				2		/* we have sent the OK/result message */

/* s2s states */
#define OSRF_CHAT_STATE_S2S_CHALLENGE			4		/* client : waiting for the challenge */
#define OSRF_CHAT_STATE_S2S_RESPONSE			5		/* server : waiting for the challenge response */
#define OSRF_CHAT_STATE_S2S_VERIFY				6		/* client : waiting for verify message */
#define OSRF_CHAT_STATE_S2S_VERIFY_RESPONSE	7		/* server : waiting for verify response */
#define OSRF_CHAT_STATE_S2S_VERIFY_FINAL		8		/* client : waiting for final verify response */

/* xml parser states */
#define OSRF_CHAT_STATE_INMESSAGE		1
#define OSRF_CHAT_STATE_INIQ				2
#define OSRF_CHAT_STATE_INUSERNAME		4
#define OSRF_CHAT_STATE_INRESOURCE		8
#define OSRF_CHAT_STATE_INS2SRESULT		16
#define OSRF_CHAT_STATE_INS2SVERIFY		32


struct __osrfChatNodeStruct {

	int sockid;			/* our socket id */

	int type;			/* 0 for client, 1 for server */

	/* for clients this is the full JID of the client that connected to this server.
		for servers it's the domain (network id) of the server we're connected to */
	char* remote;		


	int state;			/* for the various stages of connectivity and parsing */
	int xmlstate;		/* what part of the message are we currently parsing */
	int inparse;		/* true if we are currently parsing a chunk of XML.  If so, we can't 
									free the node.  we have to cache it and free it later */

	char* to;			/* The JID where the current message is being routed */

	char* domain;		/* the domain, resource, and username of our connecting entity. */ 
	char* resource;	/* for s2s nodes, resource and username will be empty . */
	char* username;

	char* authkey;		/* when doing any auth negotiation, this is the auth seed hash */
	osrfList* msgs;	/* if we're a server node we may have a pool of messages waiting to be delivered */

	xmlParserCtxtPtr parserCtx; 
	xmlDocPtr msgDoc;
	struct __osrfChatServerStruct* parent;

};
typedef struct __osrfChatNodeStruct osrfChatNode;

/*
struct __osrfChatS2SMessageStruct {
	char* toAddr;
	char* msgXML;
};
typedef struct __osrfChatS2SMessageStruct osrfChatS2SMessage;
*/

struct __osrfChatServerStruct {
	osrfHash* nodeHash; /* sometimes we need hash (remote id) lookup, sometimes we need socket id lookup */
	osrfList* nodeList;
	osrfList* deadNodes; /* collection of nodes to free when we get a chance */
	socket_manager* mgr;
	char* secret;			/* shared S2S secret */
	char* domain;			/* the domain this server hosts */
	int s2sport;
	int port;
};

typedef struct __osrfChatServerStruct osrfChatServer;


void osrfChatCacheS2SMessage( char* toAddr, char* msgXML, osrfChatNode* snode );

osrfChatNode* osrfNewChatS2SNode( char* domain, char* remote );
osrfChatNode* osrfNewChatNode( int sockid, char* domain );
void osrfChatNodeFree( void* node );

/* @param s2sSecret The Server to server secret.  OK to leave NULL if no 
	server to server communication is expected
	*/
osrfChatServer* osrfNewChatServer( char* domain, char* s2sSecret, int s2sport );

int osrfChatServerConnect( osrfChatServer* cs,  int port, int s2sport, char* listenAddr );

int osrfChatServerWait( osrfChatServer* server );
void osrfChatServerFree(osrfChatServer* cs);

void osrfChatHandleData( void* cs, 
	socket_manager* mgr, int sockid, char* data, int parent_id );


/* removes dead nodes that have been cached due to mid-parse removals */
void osrfChatCleanupClients( osrfChatServer* server );


osrfChatNode* osrfChatAddNode( osrfChatServer* server, int sockid );


void osrfChatRemoveNode( osrfChatServer* server, osrfChatNode* node );

/** pushes new data into the nodes parser */
int osrfChatPushData( osrfChatServer* server, osrfChatNode* node, char* data );


void osrfChatSocketClosed( void* blob, int sockid );

/**
  Sends msgXML to the client with remote 'toAddr'.  if we have no connection
  to 'toAddr' and the domain for 'toAddr' is different than our hosted domain
  we attempt to send the message to the domain found in 'toAddr'.
  */
int osrfChatSend( osrfChatServer* cs, osrfChatNode* node, char* toAddr, char* fromAddr, char* msgXML );

int osrfChatSendRaw( osrfChatNode* node, char* xml );


void osrfChatNodeFinish( osrfChatServer* server, osrfChatNode* node );

/* initializes the negotiation of a server to server connection */
int osrfChatInitS2S( osrfChatServer* cs, char* remote, char* toAddr, char* msgXML );


void osrfChatStartStream( void* blob );
void osrfChatStartElement( void* blob, const xmlChar *name, const xmlChar **atts );
void osrfChatEndElement( void* blob, const xmlChar* name );
void osrfChatHandleCharacter(void* blob, const xmlChar *ch, int len);
void osrfChatParseError( void* blob, const char* msg, ... );

int osrfChatHandleNewConnection( osrfChatNode* node, const char* name, const xmlChar** atts );
int osrfChatHandleConnecting( osrfChatNode* node, const char* name, const xmlChar** atts );
int osrfChatHandleConnected( osrfChatNode* node, const char* name, const xmlChar** atts );
int osrfChatHandleS2SInit( osrfChatNode* node, const char* name, const xmlChar** atts );
int osrfChatHandleS2SChallenge( osrfChatNode* node, const char* name, const xmlChar** atts );
int osrfChatHandleS2SResponse( osrfChatNode* node, const char* name, const xmlChar** atts );

int osrfChatHandleS2SConnected( osrfChatNode* node, const char* nm, const xmlChar**atts );

void osrfChatS2SMessageFree(void* n);



/* generates a random sha1 hex key */
char* osrfChatMkAuthKey();

static xmlSAXHandler osrfChatSaxHandlerStruct = {
   NULL,								/* internalSubset */
   NULL,								/* isStandalone */
   NULL,								/* hasInternalSubset */
   NULL,								/* hasExternalSubset */
   NULL,								/* resolveEntity */
   NULL,								/* getEntity */
   NULL,								/* entityDecl */
   NULL,								/* notationDecl */
   NULL,								/* attributeDecl */
   NULL,								/* elementDecl */
   NULL,								/* unparsedEntityDecl */
   NULL,								/* setDocumentLocator */
   osrfChatStartStream,			/* startDocument */
   NULL,								/* endDocument */
	osrfChatStartElement,		/* startElement */
	osrfChatEndElement,			/* endElement */
   NULL,								/* reference */
	osrfChatHandleCharacter,	/* characters */
   NULL,								/* ignorableWhitespace */
   NULL,								/* processingInstruction */
   NULL,								/* comment */
   osrfChatParseError,			/* xmlParserWarning */
   osrfChatParseError,			/* xmlParserError */
   NULL,								/* xmlParserFatalError : unused */
   NULL,								/* getParameterEntity */
   NULL,								/* cdataBlock; */
   NULL,								/* externalSubset; */
   1,
   NULL,
   NULL,								/* startElementNs */
   NULL,								/* endElementNs */
	NULL								/* xmlStructuredErrorFunc */
};

static const xmlSAXHandlerPtr osrfChatSaxHandler = &osrfChatSaxHandlerStruct;


#endif


