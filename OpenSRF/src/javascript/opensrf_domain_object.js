// -----------------------------------------------------------------------------
// This houses all of the domain object code.
// -----------------------------------------------------------------------------




// -----------------------------------------------------------------------------
// DomainObject 

DomainObject.prototype					= new domainObject();
DomainObject.prototype.constructor	= DomainObject;
DomainObject.prototype.baseClass		= domainObject.prototype.constructor;

/** Top level DomainObject class.  This most provides convience methods
  * and a shared superclass
  */
function DomainObject( name ) {
	if( name ) { this._init_domainObject( name ); }
}

/** Returns the actual element of the given domainObjectAttr. */
DomainObject.prototype._findAttr = function ( name ) {
	
	var nodes = this.element.childNodes;

	if( ! nodes || nodes.length < 1 ) {
		throw new oils_ex_dom( "Invalid xml object in _findAttr: " + this.toString() );
	}

	var i=0;
	var node = nodes.item(i);

	while( node != null ) {

		if( node.nodeName == "oils:domainObjectAttr" &&
				node.getAttribute("name") == name ) {
			return node;
		}

		node = nodes.item(++i);
	}

	return null;
}




/** Returns the value stored in the given attribute */
DomainObject.prototype.getAttr = function ( name ) {

	var node = this._findAttr( name );
	if( node ) { return node.getAttribute( "value" ); }
	else { 
		throw new oils_ex_dom( "getAttr(); Getting nonexistent attribute: " + name ); 
	}
}

/** Updates the value held by the given attribute */
DomainObject.prototype.setAttr = function ( name, value ) {

	var node = this._findAttr( name );
	if( node ) {
		node.setAttribute( "value", value );
	} else { 
		throw new oils_ex_dom( "setAttr(); Setting nonexistent attribute: " + name ); 
	}
}

/** This takes a raw DOM Element node and creates the DomainObject that the node
  * embodies and returns the object.  All new DomainObjects should be added to
  * this list if they require this type of dynamic functionality.
  * NOTE Much of this will be deprecated as move to a more JSON-centric wire protocol
  */
DomainObject.newFromNode = function( node ) {

	switch( node.getAttribute("name") ) {

		case "oilsMethod":
			return new oilsMethod().replaceNode( node );
		
		case "oilsMessage":
			return new oilsMessage().replaceNode( node );

		case "oilsResponse":
			return new oilsResponse().replaceNode( node );

		case "oilsResult":
			return new oilsResult().replaceNode( node );

		case "oilsConnectStatus":
			return new oilsConnectStatus().replaceNode( node );

		case "oilsException":
			return new oilsException().replaceNode( node );

		case "oilsMethodException":
			return new oilsMethodException().replaceNode( node );

		case "oilsScalar":
			return new oilsScalar().replaceNode( node );

		case "oilsPair":
			return new oilsPair().replaceNode( node );

		case "oilsArray":
			return new oilsArray().replaceNode( node );

		case "oilsHash":
			return new oilsHash().replaceNode( node );


	}

}



// -----------------------------------------------------------------------------
// oilsMethod

oilsMethod.prototype = new DomainObject();
oilsMethod.prototype.constructor = oilsMethod;
oilsMethod.prototype.baseClass = DomainObject.prototype.constructor;

/**
  * oilsMethod Constructor
  * 
  * @param method_name The name of the method your are sending
  * to the remote server
  * @param params_array A Javascript array of the params (any
  * Javascript data type)
  */

function oilsMethod( method_name, params_array ) {
	this._init_domainObject( "oilsMethod" );
	this.add( new domainObjectAttr( "method", method_name ) );

	if( params_array ) {
		var params = this.doc.createElement( "oils:params" );
		this.element.appendChild( params ); 
		params.appendChild( this.doc.createTextNode( 
				js2JSON( params_array ) ) ); 
	}
}


/** Locates the params node of this method */
oilsMethod.prototype._getParamsNode = function() {

	var nodes = this.element.childNodes;
	if( ! nodes || nodes.length < 1 ) { return null; }
	var x=0;
	var node = nodes.item(x);
	while( node != null ) {
		if( node.nodeName == "oils:params" ) {
			return node;
		}
		node = nodes.item(++x);
	}

	return null;
}


/** Returns an array of param objects  */
oilsMethod.prototype.getParams = function() {
	var node = this._getParamsNode();
	if(node != null ) { return JSON2js( node->textContent ); }
}



// -----------------------------------------------------------------------------
// oilsMessage

// -----------------------------------------------------------------------------
// oilsMessage message types
// -----------------------------------------------------------------------------
/** CONNECT Message type */
oilsMessage.CONNECT		= 'CONNECT';
/** DISCONNECT Message type */
oilsMessage.DISCONNECT	= 'DISCONNECT';
/** STATUS Message type */
oilsMessage.STATUS		= 'STATUS';
/** REQUEST Message type */
oilsMessage.REQUEST		= 'REQUEST';
/** RESULT Message type */
oilsMessage.RESULT		= 'RESULT';


oilsMessage.prototype = new DomainObject();
oilsMessage.prototype.constructor = oilsMessage;
oilsMessage.prototype.baseClass = DomainObject.prototype.constructor;

/** Core XML object for message passing */
function oilsMessage( type, protocol, user_auth ) {

	if( !( type && protocol) ) { 
		type = oilsMessage.CONNECT; 
		protocol = "1";
	}

	if( ! (	type == oilsMessage.CONNECT		||
				type == oilsMessage.DISCONNECT	||
				type == oilsMessage.STATUS			||
				type == oilsMessage.REQUEST		||
				type == oilsMessage.RESULT	) ) {
		throw new oils_ex_message( "Attempt to create oilsMessage with incorrect type: " + type );
	}

	this._init_domainObject( "oilsMessage" );

	this.add( new domainObjectAttr( "type", type ) );
	this.add( new domainObjectAttr( "threadTrace", 0 ) );
	this.add( new domainObjectAttr( "protocol", protocol ) );	

	if( user_auth ) { this.add( user_auth ); }

}

/** Builds a new oilsMessage from raw xml.
  * Checks are taken to make sure the xml is supposed to be an oilsMessage.  
  * If not, an oils_ex_dom exception is throw.
  */
oilsMessage.newFromXML = function( xml ) {

	try {

		if( ! xml || xml == "" ) { throw 1; }

		var doc = new DOMParser().parseFromString( xml, "text/xml" );
		if( ! doc ) { throw 1; }

		var root = doc.documentElement;
		if( ! root ) { throw 1; }

		// -----------------------------------------------------------------------------
		// There are two options here.  One is that we were provided the full message
		// xml (i.e. contains the <oils:root> tag.  The other option is that we were
		// provided just the message xml portion (top level element is the 
		// <oils:domainObject>
		// -----------------------------------------------------------------------------
		
		var element;
		if( root.nodeName == "oils:root"  ) { 

			element = root.firstChild;
			if( ! element ) { throw 1; }

		} else { 

			if( root.nodeName == "oils:domainObject" ) { 
				element = root;

			} else { throw 1; }

		}


		if( element.nodeName != "oils:domainObject" ) { throw 1; } 
		if( element.getAttribute( "name" ) != "oilsMessage" ) { throw 1; }

		return new oilsMessage().replaceNode( element );

	} catch( E ) {

		if( E && E.message ) {
			throw new oils_ex_dom( "Bogus XML for creating oilsMessage: " + E.message + "\n" + xml );

		} else {
			throw new oils_ex_dom( "Bogus XML for creating oilsMessage:\n" + xml );
		}
	}

	return msg;
}



/** Adds a copy of the given DomainObject to the message */
oilsMessage.prototype.addPayload = function( new_DomainObject ) {
	this.add( new_DomainObject );
}


/** Returns the top level DomainObject contained in this message
  *
  * Note:  The object retuturned will be the actual object, not just a 
  * generic DomainObject - e.g. oilsException.
  */
oilsMessage.prototype.getPayload = function() {
	
	var nodes = this.element.childNodes;
	var x=0;
	var node = nodes.item(0);

	while( node != null ) {

		if( node.nodeName == "oils:domainObject" ) {

			new Logger().debug( "Building oilsMessage payload from\n" + 
				new XMLSerializer().serializeToString( node ), Logger.DEBUG );
			return DomainObject.newFromNode( node );
		}
		node = nodes.item(++x);
	}

	return null;
}

oilsMessage.prototype.getUserAuth = function() {

	var nodes = this.element.getElementsByTagName( "oils:userAuth" );
	if( ! nodes ) { return null; }

	var auth_elem = nodes.item(0); // should only be one
	if ( ! auth_elem ) { return null; }

	return new userAuth().replaceNode( auth_elem );

}

/** Returns the type of the message */
oilsMessage.prototype.getType = function() {
	return this.getAttr( "type" );
}

/** Returns the message protocol */
oilsMessage.prototype.getProtocol = function() {
	return this.getAttr( "protocol" );
}

/** Returns the threadTrace */
oilsMessage.prototype.getThreadTrace = function() {
	return this.getAttr( "threadTrace" );
}

/** Sets the thread trace - MUST be an integer */
oilsMessage.prototype.setThreadTrace = function( trace ) {
	this.setAttr( "threadTrace", trace );
}

/** Increments the thread trace by 1 */
oilsMessage.prototype.updateThreadTrace = function() {
	var tt = this.getThreadTrace();
	return this.setThreadTrace( ++tt );
}





// -----------------------------------------------------------------------------
// oilsResponse


// -----------------------------------------------------------------------------
// Response codes
// -----------------------------------------------------------------------------

/**
  * Below are the various response statuses
  */
oilsResponse.STATUS_CONTINUE						= 100

oilsResponse.STATUS_OK								= 200
oilsResponse.STATUS_ACCEPTED						= 202
oilsResponse.STATUS_COMPLETE						= 205

oilsResponse.STATUS_REDIRECTED					= 307

oilsResponse.STATUS_BADREQUEST					= 400
oilsResponse.STATUS_UNAUTHORIZED					= 401
oilsResponse.STATUS_FORBIDDEN						= 403
oilsResponse.STATUS_NOTFOUND						= 404
oilsResponse.STATUS_NOTALLOWED					= 405
oilsResponse.STATUS_TIMEOUT						= 408
oilsResponse.STATUS_EXPFAILED						= 417
oilsResponse.STATUS_INTERNALSERVERERROR		= 500
oilsResponse.STATUS_NOTIMPLEMENTED				= 501
oilsResponse.STATUS_VERSIONNOTSUPPORTED		= 505


oilsResponse.prototype = new DomainObject();
oilsResponse.prototype.constructor = oilsResponse;
oilsResponse.prototype.baseClass = DomainObject.prototype.constructor;

/** Constructor.  status is the text describing the message status and
  * statusCode must correspond to one of the oilsResponse status code numbers
  */
function oilsResponse( name, status, statusCode ) {
	if( name && status && statusCode ) {
		this._initResponse( name, status, statusCode );
	}
}

/** Initializes the reponse XML */
oilsResponse.prototype._initResponse = function( name, status, statusCode ) {

	this._init_domainObject( name );
	this.add( new domainObjectAttr( "status", status ));
	this.add( new domainObjectAttr( "statusCode", statusCode ) );
}



/** Returns the status of the response */
oilsResponse.prototype.getStatus = function() {
	return this.getAttr( "status" );
}

/** Returns the statusCode of the response */
oilsResponse.prototype.getStatusCode = function() {
	return this.getAttr("statusCode");
}


oilsConnectStatus.prototype = new oilsResponse();
oilsConnectStatus.prototype.constructor = oilsConnectStatus;
oilsConnectStatus.prototype.baseClass = oilsResponse.prototype.constructor;

/** Constructor.  These give us info on our connection attempts **/
function oilsConnectStatus( status, statusCode ) {
	this._initResponse( "oilsConnectStatus", status, statusCode );
}


oilsResult.prototype = new oilsResponse();
oilsResult.prototype.constructor = oilsResult;
oilsResult.prototype.baseClass = oilsResponse.prototype.constructor;


/** Constructor.  These usually carry REQUEST responses */
function oilsResult( status, statusCode ) {
	if( status && statusCode ) {
		this._initResponse( "oilsResult", status, statusCode );
	}
}

/** Returns the top level DomainObject within this result message.
  * Note:  The object retuturned will be the actual object, not just a 
  * generic DomainObject - e.g. oilsException.
  */
oilsResult.prototype.getContent = function() {

	var nodes = this.element.childNodes;
	if( ! nodes || nodes.length < 1 ) {
		throw new oils_ex_dom("Content node for oilsResult is invalid\n" + this.toString() );
	}
	var x = 0;
	var node = nodes.item(x);
	while( node != null ) {

		if( node.nodeName == "oils:domainObject"					||
				node.nodeName == "oils:domainObjectCollection" ) {

			return DomainObject.newFromNode( node );
		}
		node = nodes.item(++x);
	}

	throw new oils_ex_dom("Content node for oilsResult is invalid\n" + this.toString() );
}


oilsException.prototype = new oilsResponse();
oilsException.prototype.constructor = oilsException;
oilsException.prototype.baseClass = oilsResponse.prototype.constructor;

/** Top level exception */
function oilsException( status, statusCode ) {
	if( status && statusCode ) {
		this._initResponse( "oilsException", status, statusCode );
	}
}


oilsMethodException.prototype = new oilsException();
oilsMethodException.prototype.constructor = oilsMethodException;
oilsMethodException.prototype.baseClass = oilsException.prototype.constructor;

/** Method exception */
function oilsMethodException( status, statusCode ) {
	if( status && statusCode ) {
		this._initResponse( "oilsMethodException", status, statusCode );
	}
}


// -----------------------------------------------------------------------------
// oilsScalar


oilsScalar.prototype = new DomainObject();
oilsScalar.prototype.constructor = oilsScalar;
oilsScalar.prototype.baseClass = DomainObject.prototype.constructor;

/** Contains a single JSON item as its text content */
function oilsScalar( value ) {
	this._init_domainObject( "oilsScalar" );
	this.element.appendChild( this.doc.createTextNode( value ) );
}

/** Returns the contained item as a Javascript object */
oilsScalar.prototype.getValue = function() {
	return JSON2js( this.element.textContent );
}


// -----------------------------------------------------------------------------
// oilsPair


oilsPair.prototype = new DomainObject()
oilsPair.prototype.constructor = oilsPair;
oilsPair.prototype.baseClass = DomainObject.prototype.constructor;

function oilsPair( key, value ) {

	this._init_domainObject( "oilsPair" );
	this.element.appendChild( this.doc.createTextNode( value ) );
	this.element.setAttribute( "key", key );
}

oilsPair.prototype.getKey = function() {
	return this.element.getAttribute( "key" );
}

oilsPair.prototype.getValue = function() {
	return this.element.textContent;
}



// -----------------------------------------------------------------------------
// oilsArray - is a domainObjectCollection that stores a list of domainObject's
// or domainObjectCollections.
// -----------------------------------------------------------------------------

oilsArray.prototype = new domainObjectCollection()
oilsArray.prototype.constructor = oilsArray;
oilsArray.prototype.baseClass = domainObjectCollection.prototype.constructor;

function oilsArray( obj_list ) {
	this._initCollection( "oilsArray" );
	if(obj_list) { this.initArray( obj_list ); }
}

// -----------------------------------------------------------------------------
// Adds the array of objects to the array, these should be actual objects, not
// DOM nodes/elements, etc.
// -----------------------------------------------------------------------------
oilsArray.prototype.initArray = function( obj_list ) {
	if( obj_array != null && obj_array.length > 0 ) {
		for( var i= 0; i!= obj_array.length; i++ ) {
			this.add( obj_array[i] );
		}
	}
}

// -----------------------------------------------------------------------------
// Returns an array of DomainObjects or domainObjectCollections.  The objects
// returned will already be 'cast' into the correct object. i.e. you will not
// receieve an array of DomainObjects, but instead an array of oilsScalar's or
// an array of oilsHashe's, etc.
// -----------------------------------------------------------------------------
oilsArray.prototype.getObjects = function() {

	var obj_list = new Array();
	var nodes = this.element.childNodes;
	var i=0;
	var node = nodes.item(i);

	while( node != null ) {

		if( node.nodeName == "oils:domainObject"					||
				node.nodeName == "oils:domainObjectCollection" ) {
			obj_list[i++] = DomainObject.newFromNode( node );
		}
		node = nodes.item(i);
	}

	return obj_list;
}


// -----------------------------------------------------------------------------
// oilsHash - an oilsHash is an oilsArray except it only stores oilsPair's
// -----------------------------------------------------------------------------

oilsHash.prototype = new oilsArray();
oilsHash.prototype.constructor = oilsHash;
oilsHash.prototype.baseClass = oilsArray.prototype.constructor;

function oilsHash( pair_array ) {
	this._initCollection("oilsHash");
	if(pair_array) { this.initArray( pair_array ); }
}

// -----------------------------------------------------------------------------
// Returns the array of oilsPairs objects that this hash contains
// -----------------------------------------------------------------------------
oilsHash.prototype.getPairs = function() {
	return this.getObjects();
}


