var USER;
var SESSION;
var PERMS = {};

function fetchUser(session) {
	if(session == null ) {
		cgi = new CGI();
		session = cgi.param('ses');
	}
	if(!session) throw "User session is not defined";
	SESSION = session;
	var request = new Request(FETCH_SESSION, session, 1 );
	request.send(true);
	var user = request.result();
	if(checkILSEvent(user)) throw user;
	USER = user;
	return user;
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
function buildOrgSel(selector, org, offset) {
	insertSelectorVal( selector, -1, 
		org.name(), org.id(), null, findOrgDepth(org) - offset );
	for( var c in org.children() )
		buildOrgSel( selector, org.children()[c], offset);
}

/** removes all child nodes in 'tbody' that have the attribute 'key' defined */
function cleanTbody(tbody, key) {
	for( var c  = 0; c < tbody.childNodes.length; c++ ) {
		var child = tbody.childNodes[c];
		if(child && child.getAttribute(key)) tbody.removeChild(child); 
	}
}
