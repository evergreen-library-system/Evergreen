#include "jserver-c_session.h"

static int xml_error_occured = 0;
static int client_sent_disconnect = 0;

jserver_session* jserver_session_init() {

	jserver_session* session = safe_malloc(sizeof(jserver_session));
	session->parser_ctxt = xmlCreatePushParserCtxt(sax_handler, session, "", 0, NULL);
	session->current_msg = xmlNewDoc(BAD_CAST "1.0");
	session->current_to = strdup("");
	session->current_from = strdup("");
	session->state = 0;
	xmlKeepBlanksDefault(0);
	return session;
}

void jserver_session_free(jserver_session* session) {
	if(session == NULL) return;

	if( session->parser_ctxt) {
		xmlFreeDoc(session->parser_ctxt->myDoc);
		xmlFreeParserCtxt(session->parser_ctxt);
	}

	free(session->current_username);
	free(session->current_resource);
	free(session->current_domain);

	xmlCleanupCharEncodingHandlers();
	xmlFreeDoc(session->current_msg);
	xmlCleanupParser();

	free(session);
}


int jserver_session_push_data(jserver_session* session, char* data) {
	if(session == NULL || data == NULL) return -1;	
	debug_handler("pushing data into xml parser: %s", data);
	xmlParseChunk(session->parser_ctxt, data, strlen(data), 0);
	if(xml_error_occured) {
		xml_error_occured = 0;
		return -1;
	}

	if(client_sent_disconnect) {
		client_sent_disconnect = 0;
		if(session->on_client_finish)
			session->on_client_finish(session->blob);
	}

	return 0;
}

void sax_start_doc(void* blob) {
	debug_handler("Starting new session doc");
}

// ---------------------------------------------------------------------------------
// Our SAX handlers 
// ---------------------------------------------------------------------------------
void sax_start_element( 
		void* blob, const xmlChar *name, const xmlChar **atts) {

	jserver_session* session = (jserver_session*) blob;
	if(!session) return;

	debug_handler("jserver-c_session received opening XML node %s", name);

	if(!strcmp(name, "stream:stream")) {

		/* opening a new session */	
		free(session->current_domain);
		session->current_domain = strdup(sax_xml_attr(atts, "to"));
		char* from_domain = sax_xml_attr(atts, "from");
		if(!from_domain) from_domain = "";

		if(session->current_domain == NULL) {
			sax_warning(session->blob, "No 'to' specified in stream opener");

		}	else {
			debug_handler("jserver-c_session received opening stream from client on domain %s", 
				session->current_domain);

			char buf[512];
			memset(buf,0,512);

			/* reply with the stock jabber login response */
			sprintf(buf, "<?xml version='1.0'?><stream:stream xmlns:stream='http://etherx.jabber.org/streams' " 
				"xmlns='jabber:client' from='%s' to='%s' version='1.0' id='d253et09iw1fv8a2noqc38f28sb0y5fc7kfmegvx'>",
				session->current_domain, from_domain);

			debug_handler("Session Sending: %s", buf);

			session->state = JABBER_STATE_CONNECTING;
			if(session->on_login_init)
				session->on_login_init(session->blob, buf);
		}
		return;
	}

	if(session->state & JABBER_STATE_CONNECTING) {
		/* during the connect shuffle, we have to store off the
			username and resource to determine the routing address */
		if(!strcmp(name,"iq"))
			session->in_iq = 1;
		if(!strcmp(name,"username"))
			session->in_uname = 1;
		if(!strcmp(name,"resource"))
			session->in_resource = 1;
	}

	if(session->state & JABBER_STATE_CONNECTED) {

		if(!strcmp(name, "message")) {
			/* opening of a new message, build a new doc */
			xmlNodePtr root = xmlNewNode(NULL, name);
			dom_add_attrs(root, atts);
			xmlNodePtr old_root = xmlDocSetRootElement(session->current_msg, root);


			free(session->current_to);

			char* from = sax_xml_attr(atts, "from");
			if(from == NULL) from = "";
			char* to = sax_xml_attr(atts, "to");
			if(to == NULL) to = "";

			session->current_to = strdup(to);

			/* free the old message tree */
			if(old_root) xmlFreeNode(old_root);

		} else {
			xmlNodePtr node = xmlNewNode(NULL, name);
			dom_add_attrs(node, atts);
			xmlAddChild(xmlDocGetRootElement(session->current_msg), node);
		}
	}
}

void sax_end_element( void* blob, const xmlChar *name) {
	jserver_session* session = (jserver_session*) blob;
	if(!session) return;

	if(session->state & JABBER_STATE_CONNECTED) {
		if(!strcmp(name, "message")) {
			if(session->on_msg_complete) {

				debug_handler("Message is complete, finishing DOC");

				/* we have to make sure the 'from' address is set.. */
				xmlNodePtr msg = xmlDocGetRootElement(session->current_msg);
				if(msg) xmlSetProp(msg, BAD_CAST "from", BAD_CAST session->current_from );
				char* string = _xml_to_string(session->current_msg);

				session->on_msg_complete(session->blob, string, 
					session->current_from, session->current_to );
				free(string);
			}
		}
	}

	if(session->state & JABBER_STATE_CONNECTING) {
		if(session->in_iq) {
			if(!strcmp(name, "iq")) {
				session->in_iq = 0;

				char buf[1024];
				memset(buf, 0, 1024);
				snprintf(buf, 1023, "%s@%s/%s", session->current_username,
						session->current_domain, session->current_resource );
				if(session->on_from_discovered) 
					session->on_from_discovered(session->blob, buf);

				free(session->current_from);
				session->current_from = strdup(buf);
				debug_handler("Set from address to %s", session->current_from);
				session->state = JABBER_STATE_CONNECTED;
				if(session->on_login_ok) 
					session->on_login_ok(session->blob);

			}
		}
	}

	if(!strcmp(name,"stream:stream")) {
		debug_handler("receive end of client session doc");
		client_sent_disconnect = 1;
	}
}

void sax_character( void* blob, const xmlChar *ch, int len) {
	jserver_session* session = (jserver_session*) blob;
	if(!session) return;

	if(session->state & JABBER_STATE_CONNECTED) {
		xmlNodePtr last = xmlGetLastChild(
			xmlDocGetRootElement(session->current_msg));
	
		xmlNodePtr txt = xmlNewTextLen(ch, len);
		xmlAddChild(last, txt);
		return;
	} 

	if(session->state & JABBER_STATE_CONNECTING) {
		if(session->in_iq) {
			if(session->in_uname) {
				free(session->current_username);
				session->current_username = strndup((char*) ch, len);
				session->in_uname = 0;
			}
	
			if(session->in_resource) {
				free(session->current_resource);
				session->current_resource = strndup((char*) ch, len);
				session->in_resource = 0;
			}
		}
		
	}
}

void  sax_warning( void* blob, const char* msg, ... ) {

	jserver_session* session = (jserver_session*) blob;
	if(!session) return;

	char buf[1024];
	memset(buf, 0,  1024);

	va_list args;
	va_start(args, msg);
	vsnprintf(buf, 1023, msg, args);
	va_end(args);
	warning_handler("XML Warning : %s", buf);
	xml_error_occured = 1;
}


void dom_add_attrs(xmlNodePtr node, const xmlChar** atts) {
	int i;
	if (node != NULL && atts != NULL) {
		for(i = 0; (atts[i] != NULL); i++) {
			if(atts[i+1]) {
				xmlNewProp(node, atts[i], atts[i+1]);
				i++;
			}
		}
	}
}

char* sax_xml_attr( const xmlChar** atts, char* attr_name ) {
	int i;
	if(attr_name == NULL) return NULL;

	if (atts != NULL) {
		for(i = 0;(atts[i] != NULL);i++) {
			if(!strcmp(atts[i], attr_name)) 
				if(atts[++i])
					return (char*) atts[i];
		}
	}
	return NULL;
}



char* _xml_to_string( xmlDocPtr doc ) {
	
	xmlBufferPtr xmlbuf = xmlBufferCreate();
	xmlNodeDump( xmlbuf, doc, xmlDocGetRootElement(doc), 0, 0);

	char* xml = strdup( (char*) (xmlBufferContent(xmlbuf)));
	xmlBufferFree(xmlbuf);

	int l = strlen(xml)-1;
	if( xml[l] == 10 || xml[l] == 13 )
		xml[l] = '\0';

	return xml;

}

