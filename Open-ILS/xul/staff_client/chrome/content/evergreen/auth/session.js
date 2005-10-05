dump('entering auth/session.js\n');

if (typeof auth == 'undefined') auth = {};
auth.session = function (controller,mw,G) {

	this.mw = mw; this.G = G; this.controller = controller;

	return this;
};

auth.session.prototype = {

	'init' : function () {

		try {
			var init = this.G.network.request(
				'open-ils.auth',
				'open-ils.auth.authenticate.init',
				[ this.controller.view.name_prompt.value ]
			);

			if (init) {

				this.key = this.G.network.request(
					'open-ils.auth',
					'open-ils.auth.authenticate.complete',
					[ 
						this.controller.view.name_prompt.value,
						hex_md5(
							init +
							hex_md5(
								this.controller.view.password_prompt.value
							)
						)
					]
				);

				this.G.error.sdump('D_AUTH','auth.session.key = ' + this.key + '\n');

				if (Number(this.key) == 0) {
					throw('Invalid name/password combination.');
				} else if (instanceOf(this.key,ex)) {
					throw(this.key.err_msg());
				}

				if (typeof this.on_init == 'function') {
					this.G.error.sdump('D_AUTH','auth.session.on_init()\n');
					this.on_init();
				}

			} else {

				var error = 'open-ils.auth.authenticate.init returned false\n';
				this.G.error.sdump('D_ERROR',error);
				this.controller.logoff();
				throw(error);
			}

		} catch(E) {
			var error = 'Error on auth.session.init(): ' + E + '\n';
			this.G.error.sdump('D_ERROR',error); 

			if (typeof this.on_init_error == 'function') {
				this.G.error.sdump('D_AUTH','auth.session.on_init_error()\n');
				this.on_init_error(E);
			}

			//throw(E);
			if (typeof this.on_init == 'function') {
				this.G.error.sdump('D_AUTH','auth.session.on_init() despite error\n');
				this.on_init();
			}
		}

	},

	'close' : function () { 
		this.G.error.sdump('D_AUTH','auth.session.close()\n'); 
		this.key = null;
		if (typeof this.G.on_close == 'function') {
			this.G.error.sdump('D_AUTH','auth.session.on_close()\n');
			this.G.on_close();
		}
	}

}

dump('exiting auth/session.js\n');
