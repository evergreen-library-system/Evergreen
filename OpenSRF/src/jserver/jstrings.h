/* ------------------------------------------------
	some pre-packaged Jabber XML
	------------------------------------------------ */

#ifndef _JSTRINGS_H_
#define _JSTRINGS_H_

#define JSTRING_START_STREAM "<?xml version='1.0'?><stream:stream xmlns:stream='http://etherx.jabber.org/streams' xmlns='jabber:client' from='%s' to='%s' version='1.0' id='d253et09iw1fv8a2noqc38f28sb0y5fc7kfmegvx'>" /* this will need to by dynamic when we add login handling */


#define JSTRING_PARSE_ERROR "<stream:stream xmlns:stream='http://etherx.jabber.org/streams' version='1.0'><stream:error xmlns:stream='http://etherx.jabber.org/streams'><xml-not-well-formed xmlns='urn:ietf:params:xml:ns:xmpp-streams'/><text xmlns='urn:ietf:params:xml:ns:xmpp-streams'>syntax error</text></stream:error></stream:stream>" 

#define JSTRING_LOGIN_OK "<iq xmlns='jabber:client' id='0123456789' type='result'/>"

#define JSTRING_NO_RECIPIENT "<message xmlns='jabber:client' type='error' from='%s' to='%s'><error type='cancel' code='404'><item-not-found xmlns='urn:ietf:params:xml:ns:xmpp-stanzas'/></error><body>NOT ADDING BODY</body></message>"

#endif
