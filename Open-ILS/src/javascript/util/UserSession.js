var globalUserSession;


function UserSession() { 

	if(globalUserSession != null) {
		return globalUserSession;
	}
	this.connected		= false;
	this.verifySession();
	this.exp_days		= null;
	globalUserSession = this; 
}

UserSession.prototype.destroy = function() {
	this.connected		= false;
	this.session_id	= null;
	this.username		= null;
	this.orgUnit		= null;
}

UserSession.prototype.verifySession = function() {

	//this.session_id		= getCookie("ils_ses");
	//this.username		= getCookie("ils_uname");

	if( this.username && this.session_id ) { 
		/* we're in the middle of an active session */
		this.connected = true;

	} else {

		if(this.session_id) {

			debug("Retrieving user information\n");

			/* user is returning to the page with a session key */
			var request = new RemoteRequest("open-ils.auth", 
				"open-ils.auth.session.retrieve", this.session_id );

			request.send(true);
			var user = request.getResultObject();

			if(user && user[0]) {

				debug("Received user object " + js2JSON(user) + "\n");
				//user = new au(user[0]);
				this.username = user.usrname();

			} else {

				this.session_id = null;
				this.username = null;
				this.connected = false;
				return;
			}

			if(this.username) {

				this.connected = true;
				setCookie("ils_uname", this.username); /* only good for this session */

			} else {

				deleteCookie("ils_ses");
				deleteCookie("ils_uname");

				this.session_id = null;
				this.username = null;
				this.connected = false;

			}
		}
	}
}


UserSession.instance = function() {
	return new UserSession();
}

/* XXX needs to be a callback */
function timed_out() {
		alert('User Session Timed Out.  \nRedirecting to start page'); 
		location.href='/'; 
}

/** Initialize a user session timeout.  */
function startSessionTimer( timeout_ms ) {
	var obj = globalUserSession;
	obj.timeout_ms = timeout_ms;
	obj.timeout_id = setTimeout( "timed_out()", timeout_ms );
	window.onmousemove = resetSessionTimer;
}

/** Reset the user session timeout.  Useful if the user is active */
function resetSessionTimer() {
	var obj = globalUserSession;
	if(obj.timeout_id != null) { clearTimeout( obj.timeout_id ); }
	obj.timeout_id = setTimeout( "timed_out()", obj.timeout_ms );
}

function destroySessionTimer() {
	var obj = globalUserSession;
	if(obj.timeout_id != null) { clearTimeout( obj.timeout_id ); }
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

	/*
	var exptime = new Date().valueOf();
	if(this.exp_days) 
		exptime = new Date(exptime + (this.exp_days * 86400000) 
	else
		exptime = new Date(exptime + (1 * 86400000)); 

	fixDate(exptime);
	setCookie("ils_ses", auth_result, exptime, "/");
	setCookie("ils_uname", username ); 
	*/

	this.connected = true;

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




