dump('entering patron/search_form.js\n');

if (typeof patron == 'undefined') patron = {};
patron.search_form = function (params) {

	JSAN.use('util.error'); this.error = new util.error();
	JSAN.use('main.network'); this.network = new main.network();
	this.w = window;
}

patron.search_form.prototype = {

	'init' : function( params ) {

		var obj = this;

		obj.session = params['session'];

		JSAN.use('OpenILS.data'); this.OpenILS = {}; 
		obj.OpenILS.data = new OpenILS.data(); obj.OpenILS.data.init({'via':'stash'});

		JSAN.use('main.controller'); obj.controller = new main.controller();
		obj.controller.init(
			{
				control_map : {
					'cmd_broken' : [
						['command'],
						function() { alert('Not Yet Implemented'); }
					],
					'cmd_patron_search_submit' : [
						['command'],
						function() {
							var query = '';
							for (var i = 0; i < obj.controller.render_list.length; i++) {
								var id = obj.controller.render_list[i][0];
								var node = document.getElementById(id);
								if (node && node.value != '') {
									if (query == '') {
										query += '?';
									} else {
										query += '&';
									}
									query += id + '=' + window.escape(node.value);
									dump('id = ' + id + '  value = ' + node.value + '\n');
								}
							}
							if (typeof obj.on_submit == 'function') {
								obj.on_submit(query);
							}
							if (typeof window.xulG == 'object' 
								&& typeof window.xulG.on_submit == 'function') {
								obj.error.sdump('D_PATRON','patron.search_form: Calling external .on_submit()\n');
								window.xulG.on_submit(query);
							} else {
								obj.error.sdump('D_PATRON','patron.search_form: No external .on_query()\n');
							}

						}
					],
					'cmd_patron_search_clear' : [
						['command'],
						function() { obj.controller.render(); }
					],
					'family_name' : [
						['render'],
						function(e) {
							return function() {
								if (params.query&&params.query.family_name) {
									e.value = params.query.family_name;
								} else {
									e.value = '';
								}
							};
						}
					],
					'first_given_name' : [
						['render'],
						function(e) {
							return function() {
								if (params.query&&params.query.first_given_name) {
									e.value = params.query.first_given_name;
								} else {
									e.value = '';
								}
							};
						}
					],
					'second_given_name' : [
						['render'],
						function(e) {
							return function() {
								if (params.query&&params.query.second_given_name) {
									e.value = params.query.second_gtiven_name;
								} else {
									e.value = '';
								}
							};
						}
					],
					'email' : [
						['render'],
						function(e) {
							return function() {
								if (params.query&&params.query.email) {
									e.value = params.query.email;
								} else {
									e.value = '';
								}
							};
						}
					],
					'phone' : [
						['render'],
						function(e) {
							return function() {
								if (params.query&&params.query.phone) {
									e.value = params.query.phone;
								} else {
									e.value = '';
								}
							};
						}
					],
					'ident' : [
						['render'],
						function(e) {
							return function() {
								if (params.query&&params.query.ident) {
									e.value = params.query.ident;
								} else {
									e.value = '';
								}
							};
						}
					],
					'street1' : [
						['render'],
						function(e) {
							return function() {
								if (params.query&&params.query.street1) {
									e.value = params.query.street1;
								} else {
									e.value = '';
								}
							};
						}
					],
					'street2' : [
						['render'],
						function(e) {
							return function() {
								if (params.query&&params.query.street2) {
									e.value = params.query.street2;
								} else {
									e.value = '';
								}
							};
						}
					],
					'city' : [
						['render'],
						function(e) {
							return function() {
								if (params.query&&params.query.city) {
									e.value = params.query.city;
								} else {
									e.value = '';
								}
							};
						}
					],
					'state' : [
						['render'],
						function(e) {
							return function() {
								if (params.query&&params.query.state) {
									e.value = params.query.state;
								} else {
									e.value = '';
								}
							};
						}
					],
					'post_code' : [
						['render'],
						function(e) {
							return function() {
								if (params.query&&params.query.post_code) {
									e.value = params.query.post_code;
								} else {
									e.value = '';
								}
							};
						}
					],
				}
			}
		);

	},

	'on_submit' : function(q) {
		var msg = 'Query = ' + q;
		this.error.sdump('D_PATRON', msg);
	},

}

dump('exiting patron/search_form.js\n');
