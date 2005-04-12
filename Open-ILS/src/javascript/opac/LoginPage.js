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
	this.login_button		= document.getElementById("login_button");

	this.login_button.onclick = loginShuffle;

	this.username		= document.getElementById("login_username");
	this.password		= document.getElementById("login_password");
	this.result_field = document.getElementById("login_result_text");

	this.username.focus();
	this.username.onkeydown = loginOnEnter;
	this.password.onkeydown = loginOnEnter;
	
	this.login_success_msg = null;
	this.login_failure_msg = null;

	this.session = UserSession.instance();

	globalLoginPage = this;
}


function loginShuffle() {
	var obj = globalLoginPage;
	if( UserSession.instance().login( obj.username.value, obj.password.value )) {
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




