dump('entering auth/controller.js\n');

if (typeof auth == 'undefined') auth = {};
auth.controller = function (mw,G) {

	this.mw = mw; this.G = G;

	return this;
};

auth.controller.prototype = {

	'init' : function () {

		var obj = this;  // so the 'this' in event handlers don't confuse us
		var mw = obj.mw;
		var G = obj.G;

		// This talks to our ILS
		JSAN.use('auth.session');
		obj.session = new auth.session(obj,mw,G);

		// Attach this object to the XUL through event listeners

		var cmd_login = mw.document.getElementById('cmd_login');
			if (cmd_login) 
				cmd_login.addEventListener('command',function () { obj.login(); },false);

		var cmd_logoff = mw.document.getElementById('cmd_logoff');
			if (cmd_logoff) 
				cmd_logoff.addEventListener('command',function () { obj.logoff(); },false);

		var cmd_close_window = mw.document.getElementById('cmd_close_window');
			if (cmd_close_window) 
				cmd_close_window.addEventListener('command',function () { obj.close(); },false);

		obj.view.name_prompt = mw.document.getElementById('name_prompt');
			if (obj.view.name_prompt) {
				obj.view.name_prompt.addEventListener('keypress',handle_keypress,false);
				obj.view.name_prompt.focus();
			}

		obj.view.password_prompt = mw.document.getElementById('password_prompt');
			if (obj.view.password_prompt)
				obj.view.password_prompt.addEventListener('keypress',handle_keypress,false);
	
		obj.view.submit_button = mw.document.getElementById('submit_button');
	
		obj.view.progress_bar = mw.document.getElementById('auth_meter');

		function handle_keypress(ev) {
			if (ev.keyCode && ev.keyCode == 13) {
				switch(this) {
					case obj.name_prompt:
						ev.preventDefault();
						obj.view.password_prompt.focus(); obj.view.password_prompt.select();
					break;
					case obj.view.password_prompt:
						ev.preventDefault();
						obj.view.submit_button.focus(); 
						obj.login();
					break;
					default: break;
				}
			}
		}

		if (typeof this.on_init == 'function') {
			this.G.error.sdump('D_AUTH','auth.controller.on_init()\n');
			this.on_init();
		}
	},

	'view' : {},

	'login' : function() { 

		this.G.error.sdump('D_AUTH','login with ' + this.view.name_prompt.value + ' and ' + this.view.password_prompt.value + '\n'); 
		this.view.name_prompt.disabled = true;
		this.view.password_prompt.disabled = true;
		this.view.submit_button.disabled = true;

		try {

			if (typeof this.on_login == 'function') {
				this.G.error.sdump('D_AUTH','auth.controller.session.on_init = ' +
					'auth.controller.on_login\n');
				this.session.on_init = this.on_login;
			}
			
			this.session.init();

		} catch(E) {
			var error = '!! ' + E + '\n';
			this.G.error.sdump('D_ERROR',error); 
			alert(error);
			this.logoff();

			if (typeof this.on_login_error == 'function') {
				this.G.error.sdump('D_AUTH','auth.controller.on_login_error()\n');
				this.on_login_error(E);
			}
		}

	},
	'logoff' : function() { 
	
		this.G.error.sdump('D_AUTH','logoff' + this.mw + '\n'); 
		this.view.progress_bar.value = 0; this.view.progress_bar.setAttribute('real','0.0');
		this.view.submit_button.disabled = false;
		this.view.password_prompt.disabled = false;
		this.view.password_prompt.value = '';
		this.view.name_prompt.disabled = false;
		this.view.name_prompt.focus(); this.view.name_prompt.select();

		this.session.close();

		if (typeof this.on_logoff == 'function') {
			this.G.error.sdump('D_AUTH','auth.controller.on_logoff()\n');
			this.on_logoff();
		}
		
	},
	'close' : function() { 
	
		this.G.error.sdump('D_AUTH','close' + this.mw + '\n');
		this.logoff();
		for (var w in this.G.window.appshell_list) {
			this.G.window.appshell_list[w].close();
		}
		this.mw.close(); /* Probably won't go any further */

		if (typeof this.on_close == 'function') {
			this.G.error.sdump('D_AUTH','auth.controller.on_close()\n');
			this.on_close();
		}
		
	}
}

dump('exiting auth/controller.js\n');
