dump('entering auth/session.js\n');

if (typeof auth == 'undefined') auth = {};
auth.session = function (view) {

	JSAN.use('util.error'); this.error = new util.error();
	JSAN.use('main.network'); this.network = new main.network();
	this.view = view;

	return this;
};

auth.session.prototype = {

	'init' : function () {

		try {
			var init = this.network.request(
				'open-ils.auth',
				'open-ils.auth.authenticate.init',
				[ this.view.name_prompt.value ]
			);

			if (init) {

				this.key = this.network.request(
					'open-ils.auth',
					'open-ils.auth.authenticate.complete',
					[ 
						this.view.name_prompt.value,
						hex_md5(
							init +
							hex_md5(
								this.view.password_prompt.value
							)
						)
					]
				);

				this.error.sdump('D_AUTH','auth.session.key = ' + this.key + '\n');

				if (Number(this.key) == 0) {
					throw('Invalid name/password combination.');
				} else if (instanceOf(this.key,ex)) {
					throw(this.key.err_msg());
				}

				if (typeof this.on_init == 'function') {
					this.error.sdump('D_AUTH','auth.session.on_init()\n');
					this.on_init();
				}

			} else {

				var error = 'open-ils.auth.authenticate.init returned false\n';
				this.error.sdump('D_ERROR',error);
				if (typeof this.on_error == 'function') {
					this.error.sdump('D_AUTH','auth.session.on_error()\n');
					this.on_error();
				}
				throw(error);
			}

		} catch(E) {
			var error = 'Error on auth.session.init(): ' + E + '\n';
			this.error.sdump('D_ERROR',error); 

			if (typeof this.on_init_error == 'function') {
				this.error.sdump('D_AUTH','auth.session.on_init_error()\n');
				this.on_init_error(E);
			}

			//throw(E);
			if (typeof this.on_init == 'function') {
				this.error.sdump('D_AUTH','auth.session.on_init() despite error\n');
				this.on_init();
			}
		}

	},

	'close' : function () { 
		this.error.sdump('D_AUTH','auth.session.close()\n'); 
		this.key = null;
		if (typeof this.G.on_close == 'function') {
			this.error.sdump('D_AUTH','auth.session.on_close()\n');
			this.G.on_close();
		}
	}

}

dump('exiting auth/session.js\n');
