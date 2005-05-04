var globalUserSession;

/* cookie fields */
UserSession.SES = 0;


function UserSession() { 
	this.cookie = new cookieObject("ses", 1, "/opac/", "ils_ses");
	this.connected		= false;
	this.exp_days		= null;
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

	if( this.session_id )
		this.cookie.put("ils_ses", this.session_id);

	debug("Persisting session with session " + 
		this.session_id + " and uname " + this.username );

	this.cookie.write();
}



UserSession.prototype.verifySession = function() {

	this.session_id = this.cookie.fields[UserSession.SES];

	if( this.session_id ) {
		debug("Found user session " + this.session_id);
	}

	if(this.session_id) {

		debug("Retrieving user information\n");

		/* user is returning to the page with a session key */
		var request = new RemoteRequest("open-ils.auth", 
			"open-ils.auth.session.retrieve", this.session_id );

		request.send(true);
		var user = request.getResultObject();

		if( typeof user == 'object' ) {

			this.username = user.usrname();
			this.connected = true;
			this.persist();
			return true;

		} else {
			this.destroy();
			return false;
		}

	} else {
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
UserSession.prototype.grabOrgUnit = function() {
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
	
	this.orgUnit = findOrgUnit(this.userObject.home_ou());
	globalSearchDepth = findOrgDepth(this.orgUnit.ou_type());
	globalSelectedDepth = findOrgDepth(this.orgUnit.ou_type());
	globalPage.updateSelectedLocation(this.orgUnit);
	globalPage.updateCurrentLocation(this.orgUnit);

	return;

}




