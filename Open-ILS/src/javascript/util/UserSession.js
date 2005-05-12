var globalUserSession;

/* cookie fields */
UserSession.SES = 0;


function UserSession() { 
	this.cookie = new cookieObject("ses", 1, "/opac/", "ils_ses");
	this.connected		= false;
	globalUserSession = this; 
}

UserSession.prototype.destroy = function() {
	debug("Removing user session");
	this.connected		= false;
	this.session_id	= null;
	this.username		= null;
	this.orgUnit		= null;
	this.cookie.remove();
}

UserSession.prototype.persist = function() {

	this.cookie = new cookieObject("ses", 1, "/opac/", "ils_ses");

	if(!this.session_id) return;

	if( this.session_id )
		this.cookie.put("ils_ses", this.session_id);

	debug("Persisting session with session " + 
		this.session_id + " and uname " + this.username );

	this.cookie.write();
	debug("Persisted session " + this.cookie.fields[UserSession.SES]);
}



UserSession.prototype.verifySession = function(ses) {

	debug("Verifying session...");
	if(ses)
		debug("Session key passed in from XUL[" + ses + "], verifying...");

	if(ses != null)
		this.session_id = ses;
	else
		this.session_id = this.cookie.fields[UserSession.SES];

	if(this.session_id) {
		debug("Retrieveing user info for session " + this.session_id);

		/* user is returning to the page with a session key */
		var request = new RemoteRequest("open-ils.auth", 
			"open-ils.auth.session.retrieve", this.session_id );

		request.send(true);
		var user = request.getResultObject();

		if( typeof user == 'object' && user._isfieldmapper) {

			this.username = user.usrname();
			this.connected = true;
			this.persist();
			return true;

		} else {
			debug("User session " + this.session_id + " is no longer valid");
			this.destroy();
			return false;
		}

	} else {
		debug("No session cookie found");
		this.destroy();
		return false;
	}
}


UserSession.instance = function() {
	if( globalUserSession )
		return globalUserSession;
	return new UserSession();
}

UserSession.prototype.setSessionId = function( id ) {
	debug("User session id " + id );
	this.session_id = id;
}

UserSession.prototype.getSessionId = function() {
	return this.session_id;
}

UserSession.prototype.login = function( username, password ) {

	if(!username || !password) { return false; }
	this.username = username;

	var init_request = new RemoteRequest( 'open-ils.auth',
		      'open-ils.auth.authenticate.init', username );

	init_request.send(true);
	var seed = init_request.getResultObject();

	if( ! seed || seed == '0') {
		/* XXX should be an exception */
		alert( "Error Communicating with Authentication Server" );
		return null;
	}

	var auth_request = new RemoteRequest( 'open-ils.auth',
			'open-ils.auth.authenticate.complete', username, 
			hex_md5(seed + hex_md5(password)));

	auth_request.send(true);
	var auth_result = auth_request.getResultObject();

	if(auth_result == '0') { return false; }

	this.setSessionId(auth_result);

	this.connected = true;

	this.persist();

	return true;
}



/* grab this users org unit */
/* if new_org_id is provided, it is used instead of the home_ou 
	of the user */
UserSession.prototype.grabOrgUnit = function(org) {
	var session = this.getSessionId();
	if(!session) {
		throw new EXLogic(
			"No session ID for user in grabOrgUnit()");
	}

	debug("Retrieving this users object");

	var request = new RemoteRequest(
			"open-ils.auth",
			"open-ils.auth.session.retrieve",
			this.session_id);
	request.send(true);
	this.userObject = request.getResultObject();
	
	if(org) 
		this.orgUnit = org;
	else	
		this.orgUnit = findOrgUnit(this.userObject.home_ou());

	globalSelectedDepth = findOrgDepth(this.orgUnit.ou_type());
	globalPage.updateSelectedLocation(this.orgUnit);
	globalPage.updateCurrentLocation(this.orgUnit);

	return;

}




