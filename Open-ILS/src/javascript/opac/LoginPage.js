LoginPage.prototype					= new Page();
LoginPage.prototype.constructor	= LoginPage;
LoginPage.baseClass					= Page.constructor;

// ---------------------------------------------------------------------------------
// login
// ---------------------------------------------------------------------------------

var globalLoginPage = null;

function LoginPage() {

	if(globalLoginPage != null) { return globalLoginPage; }

	this.searchBarForm	= new SearchBarFormChunk();
	this.searchBar			= new SearchBarChunk();
	this.login_button		= getById("login_button");

	this.login_button.onclick = loginShuffle;

	this.username		= getById("login_username");
	this.password		= getById("login_password");
	this.result_field = getById("login_result_text");

	try {this.username.focus();} catch(E) {}
	this.username.onkeydown = loginOnEnter;
	this.password.onkeydown = loginOnEnter;
	
	this.login_success_msg = null;
	this.login_failure_msg = null;

	this.session = UserSession.instance();

	globalLoginPage = this;
}

LoginPage.prototype.init = function() {
	this.searchBar.reset();
}



function loginShuffle() {
	var obj = globalLoginPage;
	var ses = UserSession.instance();
	if( ses.login( obj.username.value, obj.password.value )) {
		/* now grab the org_unit associated with this user */
		ses.grabOrgUnit();
		obj.result_field.innerHTML = obj.login_success_msg;
		obj.searchBar.reset();
	} else {
		obj.result_field.innerHTML = obj.login_failure_msg;
	}
}

function loginOnEnter(evt) {
	var code = grabCharCode(evt); 
	if(code==13||code==3) { loginShuffle(); }
}



