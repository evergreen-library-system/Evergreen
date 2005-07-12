var PopupBoxId = 0;


function LoginDialog(logged_in_callback) {
	this.callback = logged_in_callback;
	this.rand = PopupBoxId++;
}



/* node is the element the dialog should popup under */
LoginDialog.prototype.display = function(node) {

	if(UserSession.instance().verifySession()) {
		if(this.callback) this.callback(UserSession.instance());
		return;
	}

	this.box = new PopupBox(node);
	var box = this.box;
	box.title("Login");

	var ut = elem("input", {id:"login_uname_" + this.rand,type:"text",size:"16"});
	var pw = elem("input",{id:"login_passwd_" + this.rand,type:"password",size:"16"});
	ut.size = 16;
	pw.size = 16;

	var but = elem("input",
		{style:"margin-right: 10px", type:"submit",value:"Login"});
	var cancel = elem("input",
		{style:"margin-left: 10px;",type:"submit",value:"Cancel"});


	var obj = this;
	var submitFunc = function() {
		var uname = getById("login_uname_" + obj.rand).value;
		var passwd = getById("login_passwd_" + obj.rand).value;

		if(uname == null || uname == "") {
			alert("Please enter username");
			return;
		}

		if(passwd == null || passwd == "") {
			alert("Please enter password");
			return;
		}

		var ses = UserSession.instance();
		if( ses.login(uname, passwd)) {
			/* now grab the org_unit associated with this user */
			ses.grabOrgUnit();
			ses.fleshMe(true); /* flesh the user */
			obj.hideMe();
			if(obj.callback) obj.callback(ses);
		} else {
			alert("Password is incorrect");
			try{pw.focus();}catch(e){}
		}
	}

	but.onclick = submitFunc;
	ut.onkeyup = function(evt) { if(userPressedEnter(evt)) submitFunc(); }
	pw.onkeyup = function(evt) { if(userPressedEnter(evt)) submitFunc(); }
	cancel.onclick = function() { obj.hideMe(); }

	box.addText("Username ");
	box.addNode(ut);
	box.lines();
	box.addText("Passwod ");
	box.addNode(pw);
	box.lines();
	box.makeGroup([but, cancel]);
	
	box.show();
	try{ut.focus();}catch(E){}

}

function runLoginOnEnter(evt) {
	var code = grabCharCode(evt); 
	if(code==13||code==3) {  }
}


LoginDialog.prototype.hideMe = function() {
	this.box.hide();
}


