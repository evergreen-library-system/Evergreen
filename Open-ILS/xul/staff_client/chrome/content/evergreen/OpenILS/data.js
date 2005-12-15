dump('entering OpenILS/data.js\n');

if (typeof OpenILS == 'undefined') OpenILS = {};
OpenILS.data = function () {

	JSAN.use('util.error'); this.error = new util.error();
	JSAN.use('util.network'); this.network = new util.network();

	return this;
}

OpenILS.data.prototype = {

	'list' : {},
	'hash' : {},

	'init' : function (params) {

		try {
			if (params && params.via == 'stash') {	
				this.stash_retrieve();
			} else {
				this.network_retrieve();
			}
		
		} catch(E) {
			this.error.sdump('D_ERROR','Error in OpenILS.data.init('
				+js2JSON(params)+'): ' + js2JSON(E) );
		}


	},

	'stash' : function () {
		try {
			netscape.security.PrivilegeManager.enablePrivilege("UniversalXPConnect");
			const OpenILS=new Components.Constructor("@mozilla.org/openils_data_cache;1", "nsIOpenILS");
			var data_cache=new OpenILS( );
			for (var i = 0; i < arguments.length; i++) {
				this.error.sdump('D_DATA','stashing ' + arguments[i] + ' : ' + this[arguments[i]] + '\n');
				data_cache.wrappedJSObject.OpenILS.prototype.data[arguments[i]] = this[arguments[i]];
			}
		} catch(E) {
			this.error.sdump('D_ERROR','Error in OpenILS.data.stash(): ' + js2JSON(E) );
		}
	},

	'_debug_stash' : function() {
		try {
			netscape.security.PrivilegeManager.enablePrivilege("UniversalXPConnect");
			const OpenILS=new Components.Constructor("@mozilla.org/openils_data_cache;1", "nsIOpenILS");
			var data_cache=new OpenILS( );
			for (var i in data_cache.wrappedJSObject.OpenILS.prototype.data) {
				dump('_debug_stash ' + i + '\n');
			}
		} catch(E) {
			this.error.sdump('D_ERROR','Error in OpenILS.data._debug_stash(): ' + js2JSON(E) );
		}
	},

	'_fm_objects' : {

		'pgt' : [ api.fm_pgt_retrieve.app, api.fm_pgt_retrieve.method, [], true ],
		'cit' : [ api.fm_cit_retrieve.app, api.fm_cit_retrieve.method, [], true ],
		'cst' : [ api.fm_cst_retrieve.app, api.fm_cst_retrieve.method, [], true ],
		'acpl' : [ api.fm_acpl_retrieve.app, api.fm_acpl_retrieve.method, [], true ],
		'ccs' : [ api.fm_ccs_retrieve.app, api.fm_ccs_retrieve.method, [], true ],
		'aou' : [ api.fm_aou_retrieve.app, api.fm_aou_retrieve.method, [], true ],
		'aout' : [ api.fm_aout_retrieve.app, api.fm_aout_retrieve.method, [], true ]	
	},

	'stash_retrieve' : function() {
		try {
			netscape.security.PrivilegeManager.enablePrivilege("UniversalXPConnect");
			const OpenILS=new Components.Constructor("@mozilla.org/openils_data_cache;1", "nsIOpenILS");
			var data_cache=new OpenILS( );
			var dc = data_cache.wrappedJSObject.OpenILS.prototype.data;
			for (var i in dc) {
				this.error.sdump('D_DATA','Retrieving ' + i + ' : ' + dc[i] + '\n');
				this[i] = dc[i];
			}
			if (typeof this.on_complete == 'function') {

				this.on_complete();
			}
		} catch(E) {
			this.error.sdump('D_ERROR','Error in OpenILS.data._debug_stash(): ' + js2JSON(E) );
		}
	},

	'network_retrieve' : function() {
		var obj = this;

		JSAN.use('util.file');
		JSAN.use('util.functional');
		JSAN.use('util.fm_utils');

		function gen_fm_retrieval_func(classname,data) {
			var app = data[0]; var method = data[1]; var params = data[2]; var cacheable = data[3];
			return function () {

				function convert() {
					try {
						if (obj.list[classname].constructor.name == 'Array') {
							obj.hash[classname] = 
								util.functional.convert_object_list_to_hash(
									obj.list[classname]
								);
						}
					} catch(E) {

						obj.error.sdump('D_ERROR',E + '\n');
					}

				}

				try {
					obj.list[classname] = obj.network.request( app, method, params);
					convert();
					// if cacheable, store an offline copy
					if (cacheable) {
						var file = new util.file( classname );
						file.set_object( obj.list[classname] );
					}

				} catch(E) {
					// if cacheable, try offline
					if (cacheable) {
						try {
							var file = new util.file( classname );
							obj.list[classname] = file.get_object();
							convert();
						} catch(E) {
							throw(E);
						}
					} else {
						throw(E); // for now
					}
				}
			}
		}

		this.chain = [];

		this.chain.push(
			function() {
				var f = gen_fm_retrieval_func(
					'au',
					[
						api.fm_au_retrieve_via_session.app,
						api.fm_au_retrieve_via_session.method,
						[ obj.session ],
						false
					]
				);
				try {
					f();
				} catch(E) {
					// Probably the one thing we should not cache, so what do we do?
					obj.list.au = new au();
					obj.list.au.home_lib( '1' );
				}
				obj.list.au = [ obj.list.au ];
			}
		);

		obj.error.sdump('D_DEBUG','_fm_objects = ' + js2JSON(this._fm_objects) + '\n');

		for (var i in this._fm_objects) {
			this.chain.push( gen_fm_retrieval_func(i,this._fm_objects[i]) );
		}

		// The previous org_tree call returned a tree, not a list or hash.
		this.chain.push(
			function () {
				obj.org_tree = obj.list.aou;
				obj.list.aou = util.fm_utils.flatten_ou_branch( obj.org_tree );
				obj.hash.aou = util.functional.convert_object_list_to_hash( obj.list.aou );
			}
		);

		this.chain.push(
			gen_fm_retrieval_func('my_aou', 
				[ 
					api.fm_aou_retrieve_related_via_session.app,
					api.fm_aou_retrieve_related_via_session.method,
					[ obj.session ],
					true
				]
			)
		);

		// Do this after we get the user object
		this.chain.push(

			function () {

				gen_fm_retrieval_func( 'my_actsc', 
					[ 
						api.fm_actsc_retrieve_via_aou.app,
						api.fm_actsc_retrieve_via_aou.method,
						[ obj.session, obj.list.au[0].home_ou() ],
						true
					]
				)();
			}
		);

		if (typeof this.on_complete == 'function') {

			this.chain.push( this.on_complete );
		}
		JSAN.use('util.exec'); this.exec = new util.exec();
		this.exec.on_error = function(E) { 
		
			if (typeof obj.on_error == 'function') {
				obj.on_error();
			} else {
				alert('oops: ' + E ); 
			}
		}

		this.exec.chain( this.chain );

	}
}

dump('exiting OpenILS/data.js\n');
