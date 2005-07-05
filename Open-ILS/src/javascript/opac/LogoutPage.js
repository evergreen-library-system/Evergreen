LogoutPage.prototype					= new Page();
LogoutPage.prototype.constructor	= LogoutPage;
LogoutPage.baseClass					= Page.constructor;

// ---------------------------------------------------------------------------------
// logout
// ---------------------------------------------------------------------------------

var globalLogoutPage = null;

function LogoutPage() {

	if(globalLogoutPage != null) { return globalLogoutPage; }
	this.session = UserSession.instance();
	this.searchBarForm	=	new SearchBarFormChunk();
	this.searchBar			= new SearchBarChunk();
	globalLogoutPage = this;
}

LogoutPage.prototype.doLogout = function() {

	deleteCookie("ils_uname");
	deleteCookie("ils_ses");

	if( this.session.session_id ) {
		var request = new RemoteRequest( "open-ils.auth",
			"open-ils.auth.session.delete", this.session.session_id );
		request.send(true);
		var response = request.getResultObject();
		if(! response ) {
			//alert("error logging out"); /* exception */
		}
	}

	this.session.destroy();

	var message = getById("logout_msg");
	message.innerHTML = this.logout_success_msg;
	this.searchBar.reset();

	return true;

}






