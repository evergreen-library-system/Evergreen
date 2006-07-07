dump('entering auth/session.js\n');

if (typeof auth == 'undefined') auth = {};
auth.session = function (view,login_type) {

	JSAN.use('util.error'); this.error = new util.error();
	JSAN.use('util.network'); this.network = new util.network();
	this.view = view;
	this.login_type = login_type || 'staff';

	return this;
};

auth.session.prototype = {

	'init' : function () {

		var obj = this;

		try {
			var init = this.network.request(
				api.AUTH_INIT.app,
				api.AUTH_INIT.method,
				[ this.view.name_prompt.value ]
			);

			if (init) {
				JSAN.use('OpenILS.data'); var data = new OpenILS.data(); data.stash_retrieve();

				var params = { 
					'username' : this.view.name_prompt.value,
					'password' : hex_md5(
						init +
						hex_md5(
							this.view.password_prompt.value
						)
					),
					'type' : 'temp',
				};

				if (data.ws_info[ this.view.server_prompt.value ]) {
					params.type = this.login_type;
					params.workstation = data.ws_info[ this.view.server_prompt.value ].name;
					data.ws_name = params.workstation; data.stash('ws_name');
				}

				var robj = this.network.simple_request( 'AUTH_COMPLETE', [ params ]);

				switch (robj.ilsevent) {
					case 0:
						this.key = robj.payload.authtoken;
						this.authtime = robj.payload.authtime;
					break;
					case 1520 /* WORKSTATION_NOT_FOUND */:
						alert(params.workstation + ' is not registered with this server.');
						delete(params.workstation);
						delete(data.ws_info[ this.view.server_prompt.value ]);
						data.stash('ws_info');
						data.ws_name = null; data.stash('ws_name');
						params.type = 'temp';
						robj = this.network.simple_request('AUTH_COMPLETE',[ params ]);
						if (robj.ilsevent == 0) {
							this.key = robj.payload.authtoken;
							this.authtime = robj.payload.authtime;
						} else {
							this.error.standard_unexpected_error_alert('auth.session.init',robj);
							throw(robj);
						}
					break;
					default:
					obj.error.standard_unexpected_error_alert('auth.session.init',robj);
					throw(robj);
					break;
				}

				this.error.sdump('D_AUTH','auth.session.key = ' + this.key + '\n');

				if (typeof this.on_init == 'function') {
					this.error.sdump('D_AUTH','auth.session.on_init()\n');
					this.on_init();
				}

			} else {

				var error = 'open-ils.auth.authenticate.init returned false\n';
				this.error.sdump('D_ERROR',error);
				throw(error);
			}

		} catch(E) {
			obj.error.standard_unexpected_error_alert('Error on auth.session.init()',E); 

			if (typeof this.on_init_error == 'function') {
				this.error.sdump('D_AUTH','auth.session.on_init_error()\n');
				this.on_init_error(E);
			}
			if (typeof this.on_error == 'function') {
				this.error.sdump('D_AUTH','auth.session.on_error()\n');
				this.on_error();
			}

			//throw(E);
			/* This was for testing
			if (typeof this.on_init == 'function') {
				this.error.sdump('D_AUTH','auth.session.on_init() despite error\n');
				this.on_init();
			}
			*/
		}
	},

	'close' : function () { 
		var obj = this;
		obj.error.sdump('D_AUTH','auth.session.close()\n'); 
		if (obj.key) obj.network.request(
			api.AUTH_DELETE.app,
			api.AUTH_DELETE.method,
			[ obj.key ],
			function(req) {}
		);
		obj.key = null;
		if (typeof obj.on_close == 'function') {
			obj.error.sdump('D_AUTH','auth.session.on_close()\n');
			obj.on_close();
		}
	}

}

dump('exiting auth/session.js\n');
