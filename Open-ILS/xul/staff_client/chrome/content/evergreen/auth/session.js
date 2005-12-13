dump('entering auth/session.js\n');

if (typeof auth == 'undefined') auth = {};
auth.session = function (view) {

	JSAN.use('util.error'); this.error = new util.error();
	JSAN.use('util.network'); this.network = new util.network();
	this.view = view;

	return this;
};

auth.session.prototype = {

	'init' : function () {

		try {
			var init = this.network.request(
				api.auth_init.app,
				api.auth_init.method,
				[ this.view.name_prompt.value ]
			);

			if (init) {

				var robj = this.network.request(
					api.auth_complete.app,
					api.auth_complete.method,
					[ 
						this.view.name_prompt.value,
						hex_md5(
							init +
							hex_md5(
								this.view.password_prompt.value
							)
						),
						'staff'
					]
				);

				if (robj.ilsevent == 0) {
					this.key = robj.payload.authtoken;
					this.authtime = robj.payload.authtime;
				} else {
					var error = robj.ilsevent + ' : ' + this.error.get_ilsevent( robj.ilsevent );
					this.error.sdump('D_AUTH','auth.session.init: ' + error + '\n');
					alert( error );
					throw(robj);
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
			var error = 'Error on auth.session.init(): ' + js2JSON(E) + '\n';
			this.error.sdump('D_ERROR',error); 

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
		this.error.sdump('D_AUTH','auth.session.close()\n'); 
		this.key = null;
		if (typeof this.on_close == 'function') {
			this.error.sdump('D_AUTH','auth.session.on_close()\n');
			this.on_close();
		}
	}

}

dump('exiting auth/session.js\n');
