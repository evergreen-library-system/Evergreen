/** @file oils_dom_element.js
  * -----------------------------------------------------------------------------
  * This file holds all of the core OILS DOM elements.
  *  -----------------------------------------------------------------------------

  * -----------------------------------------------------------------------------
  * Make sure you load md5.js into  your script/html/etc. before loading this 
  * file
  * -----------------------------------------------------------------------------
  * 
  * -----------------------------------------------------------------------------
  * 1. Use these if you are running via xpcshell, but not if you are running
  * 	directly from mozilla.
  * 2. BTW. XMLSerializer doesn't like being run outside of mozilla, so
  *		toString() fails.
  * 
  * var DOMParser = new Components.Constructor(
  * 		"@mozilla.org/xmlextras/domparser;1", "nsIDOMParser" );
  * 
  * 	var XMLSerializer = new Components.Constructor(
  * 		"@mozilla.org/xmlextras/xmlserializer;1", "nsIDOMSerializer" );
  *  -----------------------------------------------------------------------------
  * 
  * 
  */

/**
  *  -----------------------------------------------------------------------------
  *  DOM - Top level generic class
  *  -----------------------------------------------------------------------------
  */

function DOM() { 
	this.doc = null; 
	this.root = null;
	this.element = null;
}

/** Returns a string representation of the XML doc.  If full_bool
  * is true, it will return the entire doc and not just the relevant
  * portions (i.e. our object's element).
  */
DOM.prototype.toString = function(full_bool) {
	if( full_bool ) {
		return new XMLSerializer().serializeToString(this.doc);
	} else {
		return new XMLSerializer().serializeToString(this.element);
	}
}

/** Initializes a document and sets this.doc, this.root and this.element */
DOM.prototype.init = function( elementName ) {
	
	this.doc = new DOMParser().parseFromString( 
		"<?xml version='1.0' encoding='UTF-8'?><oils:root xmlns:oils='http://open-ils.org/namespaces/oils_v1'></oils:root>", "text/xml" );
	this.root = this.doc.documentElement;
	this.element = this.doc.createElement( "oils:" + elementName );
	return this.element;
}

/** Good for creating objects from raw xml.  This builds a new doc and inserts
  * the node provided.  So you can build a dummy object, then call replaceNode  
  * with the new xml to build an object from XML on the fly.
  */
DOM.prototype._replaceNode = function( name, new_element ) {

	var node = this.doc.importNode( new_element, true );

	if( node.nodeName != "oils:" + name ) {
		throw new oils_ex_dom( "Invalid Tag to " + name + "::replaceNode()" );
	}

	this.doc = new DOMParser().parseFromString( 
		"<?xml version='1.0' encoding='UTF-8'?><oils:root xmlns:oils='http://open-ils.org/namespaces/oils_v1'></oils:root>", "text/xml" );
	this.root = this.doc.documentElement;

	this.root.appendChild( node );
	this.element = this.root.firstChild;
	return this;
}



// -----------------------------------------------------------------------------
// domainObjectAttr
// -----------------------------------------------------------------------------

domainObjectAttr.prototype	= new DOM();
domainObjectAttr.prototype.constructor = domainObjectAttr;
domainObjectAttr.baseClass	= DOM.prototype.constructor;

/** A domainObjectAttr is a single XML node with 'name' and 'value' attributes */
function domainObjectAttr( name, value ) {

	var node = this.init( "domainObjectAttr" );
	if( ! name && value ) { return; }
	node.setAttribute( "name", name );
	node.setAttribute( "value", value );
	this.root.appendChild( node );
}


/** Returns the attribute name */
domainObjectAttr.prototype.getName = function() {
	return this.element.getAttribute("name"); 
}

/** Returns the attribut value. */
domainObjectAttr.prototype. getValue = function() {
	return this.element.getAttribute("value"); 
}

/** Sets the attribute value. */
domainObjectAttr.prototype. setValue = function( value ) {
	return this.element.setAttribute("value", value ); 
}

/** Pass in the this.element component of a domainObjectAttr and this will
  * replace the old element with the new one 
  */
domainObjectAttr.prototype.replaceNode = function( domainObjectAttr_element ) {
	return this._replaceNode( "domainObjectAttr", domainObjectAttr_element );
}

// -----------------------------------------------------------------------------
// userAuth
// -----------------------------------------------------------------------------


userAuth.prototype = new DOM();
userAuth.prototype.constructor = userAuth;
userAuth.baseClass = DOM.prototype.constructor;

function userAuth( username, secret ) {

	var node = this.init( "userAuth" );
	if( !( username && secret) ) { return; }
	node.setAttribute( "username", username );

	//There is no way to specify the hash seed with the 
	//md5 utility provided
	var hash = hex_md5( secret );
	node.setAttribute( "secret", hash );
	node.setAttribute( "hashseed", "" ); 

	this.root.appendChild( node );
}

userAuth.prototype.getUsername = function() {
	return this.element.getAttribute( "username" );
}

userAuth.prototype.getSecret = function() {
	return this.element.getAttribute( "secret" );
}

userAuth.prototype.getHashseed = function() {
	return this.element.getAttribute( "hashseed" );
}

userAuth.prototype.replaceNode = function( userAuth_element ) {
	return this._replaceNode( "userAuth", userAuth_element );
}


// -----------------------------------------------------------------------------
// domainObject
// -----------------------------------------------------------------------------

domainObject.prototype = new DOM(); 
domainObject.baseClass = DOM.prototype.constructor;
domainObject.prototype.constructor = domainObject;

/** Holds the XML for a DomainObject (see oils_domain_object.js or the DomainObject class) */
function domainObject( name ) {
	this._init_domainObject( name ); 
}

/** Initializes the domainObject XML node */
domainObject.prototype._init_domainObject = function( name ) {

	var node = this.init( "domainObject" );

	if( ! name ) { return; }
	node.setAttribute( "name", name );
	this.root.appendChild( node ); 

}

/** Pass in any DOM Element or DomainObject and this method will as the
  * new object as the next child of the root (domainObject) node 
  */
domainObject.prototype.add = function( new_DOM ) {

	this.element.appendChild( 
			new_DOM.element.cloneNode( true ) );
}

/** Removes the original domainObject XML node and replaces it with the
  * one provided.  This is useful for building new domainObject's from
  * raw xml.  Just create a new one, then call replaceNode with the new XML.
  */
domainObject.prototype.replaceNode = function( domainObject_element ) {
	return this._replaceNode( "domainObject", domainObject_element );
}



// -----------------------------------------------------------------------------
// Param 
// -----------------------------------------------------------------------------


param.prototype = new DOM();
param.baseClass = DOM.prototype.constructor;
param.prototype.constructor = param;

function param( value ) {
	var node = this.init( "param" );
	node.appendChild( this.doc.createTextNode( value ) );
	this.root.appendChild( node );
}

param.prototype.getValue = function() {
	return this.element.textContent;
}

param.prototype.replaceNode = function( param_element ) {
	return this._replaceNode( "param", param_element );
}


// -----------------------------------------------------------------------------
// domainObjectCollection
// -----------------------------------------------------------------------------

domainObjectCollection.prototype = new DOM();
domainObjectCollection.prototype.constructor = 
	domainObjectCollection;
domainObjectCollection.baseClass = DOM.prototype.constructor;

function domainObjectCollection( name ) {
	var node = this.init( "domainObjectCollection" );	
	this.root.appendChild( node );
	if(name) { this._initCollection( name ); }
}

domainObjectCollection.prototype._initCollection = function( name ) {
	if( name ) {
		this.element.setAttribute( "name", name );
	}
}

domainObjectCollection.prototype.add = function( new_domainObject ) {
	this.element.appendChild( 
			new_domainObject.element.cloneNode( true ) );
}

domainObjectCollection.prototype.replaceNode = function( new_node ) {
	return this._replaceNode( "domainObjectCollection", new_node );
}


