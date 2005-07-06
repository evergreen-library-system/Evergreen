/* node is where we attache the div */
function LoginDialog(node, logged_in_callback) {
	this.node = node;
	this.callback = logged_in_callback;
}

/* node is the element the dialog should popup under */
LoginDialog.prototype.display = function(node) {

	if(UserSession.instance().verifySession()) {
		if(this.callback) this.callback(UserSession.instance());
		return;
	}

	this.div = elem("div",{id:"login_dialog"});
	var div = this.div;
	if(IE) div.style.width = "200px"; /* just has to be done */

	add_css_class(div,"login_dialog");
	var ut = elem("input", {id:"login_uname",type:"text",size:"16"});
	var pw = elem("input",{id:"login_passwd",type:"password",size:"16"});

	var but = elem("input",
		{style:"margin-right: 10px", type:"submit",value:"Login"});
	var cancel = elem("input",
		{style:"margin-left: 10px;",type:"submit",value:"Cancel"});


	var obj = this;
	var submitFunc = function() {
		var uname = getById("login_uname").value;
		var passwd = getById("login_passwd").value;

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

	var A = getXYOffsets(node);
	div.style.left = A[0];
	div.style.top = A[1];

	div.appendChild(elem("br"));
	div.appendChild(mktext("Username "));
	div.appendChild(ut);
	div.appendChild(elem("br"));
	div.appendChild(elem("br"));
	div.appendChild(mktext("Password "));
	div.appendChild(pw);
	div.appendChild(elem("br"));
	div.appendChild(elem("br"));

	var bdiv = elem("div");
	add_css_class(bdiv, "holds_window_buttons");
	bdiv.appendChild(but);
	bdiv.appendChild(cancel);
	div.appendChild(bdiv);


	div.appendChild(elem("br"));
	this.node.appendChild(this.div);

	try{ut.focus();}catch(E){}
}

function runLoginOnEnter(evt) {
	var code = grabCharCode(evt); 
	if(code==13||code==3) {  }
}



LoginDialog.prototype.hideMe = function() {
	this.node.removeChild(this.div);
}
