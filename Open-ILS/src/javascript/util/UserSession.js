var globalUserSession;

/* cookie fields */
UserSession.SES = 0;


function UserSession() { 
	this.cookie = new cookieObject("ses", 1, "/opac/", "ils_ses");
	this.connected		= false;
	globalUserSession = this; 
	this.fleshed		= false;
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
		debug("Session key passed in [" + ses + "], verifying...");

	if(ses != null)
		this.session_id = ses;
	else
		this.session_id = this.cookie.fields[UserSession.SES];

	if(this.session_id && this.userObject && this.username && this.connected) {
		return true;
	}

	if(this.session_id) {
		debug("Retrieveing user info for session " + this.session_id);

		/* user is returning to the page with a session key */
		var request = new RemoteRequest("open-ils.auth", 
			"open-ils.auth.session.retrieve", this.session_id );

		debug("1");
		request.send(true);
		debug("2");
		var user = request.getResultObject();
		debug("3");

		if( typeof user == 'object' && user._isfieldmapper) {

			debug("User retrieved, setting up user info");
			this.username = user.usrname();
			this.userObject = user;
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
			hex_md5(seed + hex_md5(password)), "opac");

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
	
	if(org) this.orgUnit = org;
	else this.orgUnit = findOrgUnit(this.userObject.home_ou());

	if(!paramObj.__depth && this.orgUnit)
		globalSelectedDepth = findOrgDepth(this.orgUnit.ou_type());
	if(!paramObj.__location && this.orgUnit)
		globalPage.updateSelectedLocation(this.orgUnit);

	globalPage.updateCurrentLocation(this.orgUnit);

	return;
}




UserSession.prototype.updatePassword = function(currentPassword, password) {
	if(!password || !currentPassword) return null;

	var request = new RemoteRequest(
		"open-ils.actor",
		"open-ils.actor.user.password.update",
		this.getSessionId(),
		password, 
		currentPassword );

	request.send(true);
	var resp;

	try { resp = request.getResultObject(); }
	catch(E) { 
		if(instanceOf(E, ex))
			alert(E.err_msg());
		else
			alert(E);
		return false;
	}

	if(resp) {
		this.password = password;
		this.userObject.passwd(password);
		return true;
	}

	return false;
}


UserSession.prototype.updateUsername = function(username) {
	if(!username) return null;
	var request = new RemoteRequest(
		"open-ils.actor",
		"open-ils.actor.user.username.update",
		this.getSessionId(),
		username );
	request.send(true);
	var resp = request.getResultObject();
	if(resp) {
		this.username = username;
		this.userObject.usrname(username);
		return true;
	}
	return false;
}

UserSession.prototype.updateEmail = function(email) {
	if(!email) return null;
	var request = new RemoteRequest(
		"open-ils.actor",
		"open-ils.actor.user.email.update",
		this.getSessionId(),
		email );
	request.send(true);
	var resp = request.getResultObject();
	if(resp) {
		this.userObject.email(email);
		return true;
	}
	return false;
}


UserSession.prototype.fleshMe = function(force) {
	if(this.fleshed && !force) return;

	var req = new RemoteRequest(
		"open-ils.actor",
		"open-ils.actor.user.fleshed.retrieve",
		this.session_id, this.userObject.id());

	req.send(true);
	this.userObject = req.getResultObject();
	this.username = this.userObject.usrname();
	this.fleshed = true;
}





