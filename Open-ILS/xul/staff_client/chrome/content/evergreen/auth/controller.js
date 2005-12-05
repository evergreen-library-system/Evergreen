dump('entering auth/controller.js\n');

if (typeof auth == 'undefined') auth = {};
auth.controller = function (params) {
	JSAN.use('util.error'); this.error = new util.error();
	this.w = params.window;

	return this;
};

auth.controller.prototype = {

	'init' : function () {

		var obj = this;  // so the 'this' in event handlers don't confuse us
		var w = obj.w;

		// MVC
		JSAN.use('main.controller'); obj.controller = new main.controller();
		obj.controller.init(
			{
				'control_map' : {
					'cmd_login' : [
						['command'],
						function() {
							obj.login();
						}
					],
					'cmd_logoff' : [
						['command'],
						function() {
							obj.logoff()
						}
					],
					'cmd_close_window' : [
						['command'],
						function() {
							obj.close()
						}
					],
					'name_prompt' : [
						['keypress'],
						handle_keypress
					],
					'password_prompt' : [
						['keypress'],
						handle_keypress
					],
					'submit_button' : [
						['render'],
						function(e) { return function() {} }
					],
					'progress_bar' : [
						['render'],
						function(e) { return function() {} }
					]
				}
			}
		);
		obj.controller.view.name_prompt.focus();

		function handle_keypress(ev) {
			if (ev.keyCode && ev.keyCode == 13) {
				switch(this) {
					case obj.controller.view.name_prompt:
						ev.preventDefault();
						obj.controller.view.password_prompt.focus(); obj.controller.view.password_prompt.select();
					break;
					case obj.controller.view.password_prompt:
						ev.preventDefault();
						obj.controller.view.submit_button.focus(); 
						obj.login();
					break;
					default: break;
				}
			}
		}

		// This talks to our ILS
		JSAN.use('auth.session');
		obj.session = new auth.session(obj.controller.view);

		if (typeof this.on_init == 'function') {
			this.error.sdump('D_AUTH','auth.controller.on_init()\n');
			this.on_init();
		}
	},

	'login' : function() { 

		var obj = this;

		this.error.sdump('D_AUTH','login with ' 
			+ this.controller.view.name_prompt.value + ' and ' 
			+ this.controller.view.password_prompt.value + '\n'
		); 
		this.controller.view.name_prompt.disabled = true;
		this.controller.view.password_prompt.disabled = true;
		this.controller.view.submit_button.disabled = true;

		try {

			if (typeof this.on_login == 'function') {
				this.error.sdump('D_AUTH','auth.controller.session.on_init = ' +
					'auth.controller.on_login\n');
				this.session.on_init = this.on_login;
				this.session.on_error = function() { obj.logoff(); };
			}
			
			this.session.init();

		} catch(E) {
			var error = '!! ' + E + '\n';
			this.error.sdump('D_ERROR',error); 
			alert(error);
			this.logoff();

			if (typeof this.on_login_error == 'function') {
				this.error.sdump('D_AUTH','auth.controller.on_login_error()\n');
				this.on_login_error(E);
			}
		}

	},
	'logoff' : function() { 
	
		this.error.sdump('D_AUTH','logoff' + this.w + '\n'); 
		this.controller.view.progress_bar.value = 0; 
		this.controller.view.progress_bar.setAttribute('real','0.0');
		this.controller.view.submit_button.disabled = false;
		this.controller.view.password_prompt.disabled = false;
		this.controller.view.password_prompt.value = '';
		this.controller.view.name_prompt.disabled = false;
		this.controller.view.name_prompt.focus(); 
		this.controller.view.name_prompt.select();

		this.session.close();

		if (typeof this.on_logoff == 'function') {
			this.error.sdump('D_AUTH','auth.controller.on_logoff()\n');
			this.on_logoff();
		}
		
	},
	'close' : function() { 
	
		this.error.sdump('D_AUTH','close' + this.w + '\n');
		this.logoff();
		//Basically, we want to close all the windows for this application (and in case we're running this as
		//a firefox extension, we don't want to merely shutdown mozilla).  I'll probably create an XPCOM for
		//tracking the windows.
		//for (var w in this.G.window.appshell_list) {
		//	this.G.window.appshell_list[w].close();
		//}
		this.w.close(); /* Probably won't go any further */

		if (typeof this.on_close == 'function') {
			this.error.sdump('D_AUTH','auth.controller.on_close()\n');
			this.on_close();
		}
		
	}
}

dump('exiting auth/controller.js\n');
