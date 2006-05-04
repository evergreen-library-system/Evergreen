var USER;
var SESSION;
var PERMS = {};
var ORG_CACHE = {};

var XML_ELEMENT_NODE = 1;
var XML_TEXT_NODE = 3;

var FETCH_ORG_UNIT = "open-ils.actor:open-ils.actor.org_unit.retrieve";

function debug(str) { try { dump(str + '\n'); } catch(e){} }

function fetchUser(session) {
	if(session == null ) {
		cgi = new CGI();
		session = cgi.param('ses');
	}
	if(!session) throw "User session is not defined";
	SESSION = session;
	var request = new Request(FETCH_SESSION, session, 1);
	request.send(true);
	var user = request.result();
	if(checkILSEvent(user)) throw user;
	USER = user;
	return user;
}

/* if defined, callback will get the user object asynchronously */
function fetchFleshedUser(id, callback) {
	if(id == null) return null;
	var req = new Request(
		'open-ils.actor:open-ils.actor.user.fleshed.retrieve', SESSION, id );

	if( callback ) {
		req.callback( function(r){callback(r.getResultObject());} );
		req.send();

	} else {
		req.send(true);
		return req.result();
	}
}

/**
  * Fetches the highest org at for each perm  and stores the value in
  * PERMS[ permName ].  It also returns the org list to the caller
  */
function fetchHighestPermOrgs( session, userId, perms ) {
	var req = new RemoteRequest(
		'open-ils.actor',
		'open-ils.actor.user.perm.highest_org.batch', 
		session, userId, perms  );
	req.send(true);
	var orgs = req.getResultObject();
	for( var i = 0; i != orgs.length; i++ ) 
		PERMS[ perms[i] ] = ( orgs[i] != null ) ? orgs[i] : -1 ;
	return orgs;
}

/* offset is the depth of the highest org 
	in the tree we're building 
  */

/* XXX Moved to opac_utils.js */

/*
function buildOrgSel(selector, org, offset) { 
	insertSelectorVal( selector, -1, 
		org.name(), org.id(), null, findOrgDepth(org) - offset );
	for( var c in org.children() )
		buildOrgSel( selector, org.children()[c], offset);
}
*/

/** removes all child nodes in 'tbody' that have the attribute 'key' defined */
function cleanTbody(tbody, key) {
	for( var c  = 0; c < tbody.childNodes.length; c++ ) {
		var child = tbody.childNodes[c];
		if(child && child.getAttribute(key)) tbody.removeChild(child); 
	}
}


/** Inserts a row into a specified place in a table
  * tbody is the table body
  * row is the context row after which the new row is to be inserted
  * newRow is the new row to insert
  */
function insRow( tbody, row, newRow ) {
	if(row.nextSibling) tbody.insertBefore( newRow, row.nextSibling );
	else{ tbody.appendChild(newRow); }
}


/** Checks to see if a given node should be enabled
  * A node should be enabled if the itemOrg is lower in the
  * org tree than my permissions allow editing
  * I.e. I can edit the context item because it's "below" me
  */
function checkDisabled( node, itemOrg, perm ) {
	var itemDepth = findOrgDepth(itemOrg);
	var mydepth = findOrgDepth(PERMS[perm]);
	if( mydepth != -1 && mydepth <= itemDepth ) node.disabled = false;
}


function fetchOrgUnit(id, callback) {

	if(ORG_CACHE[id]) return ORG_CACHE[id];
	var req = new Request(FETCH_ORG_UNIT, SESSION, id);	

	if(callback) {
		req.callback(
			function(r) { 
				var org = r.getResultObject();
				ORG_CACHE[id] = org;
				callback(org); 
			}
		);
		req.send();

	} else {
		req.send(true);
		var org = req.result();
		ORG_CACHE[id] = org;
		return org;
	}
}
