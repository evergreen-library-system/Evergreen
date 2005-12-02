dump('entering OpenILS/data.js\n');

if (typeof OpenILS == 'undefined') OpenILS = {};
OpenILS.data = function (auth) {

	this.auth = auth;

	JSAN.use('util.error'); this.error = new util.error();
	JSAN.use('main.network'); this.network = new main.network();

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
					'open-ils.search',
					'open-ils.search.actor.user.session',
					[ obj.auth.session.key ],
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
				'open-ils.actor', 
				'open-ils.actor.org_unit.full_path.retrieve', 
				[ obj.auth.session.key ],
				true
			]
		)
	);

	// Do this after we get the user object
	this.chain.push(

		function () {

			gen_fm_retrieval_func( 'my_actsc', 
				[ 
					'open-ils.circ', 
					'open-ils.circ.stat_cat.actor.retrieve.all', 
					[ obj.auth.session.key, obj.list.au.home_ou() ],
					true
				]
			)();
		}
	);

	return this;
};

OpenILS.data.prototype = {

	'list' : {},
	'hash' : {},

	'init' : function (stash) {

		if (stash) {

			try {
				const OpenILS=new Components.Constructor("@mozilla.org/openils_data_cache;1", "nsIOpenILS");
				var data_cache=new OpenILS( );
				this.list = data_cache.wrappedJSObject.OpenILS.prototype.data.list;
				this.hash = data_cache.wrappedJSObject.OpenILS.prototype.data.hash;
			} catch(E) {
				this.error.sdump('D_ERROR','Error in OpenILS.data.init(true): ' + js2JSON(E) );
			}

			if (typeof this.on_complete == 'function') {

				this.on_complete();
			}

		} else {
			if (typeof this.on_complete == 'function') {

				this.chain.push( this.on_complete );
			}

			JSAN.use('util.exec');
			util.exec.chain( this.chain );
		}
	},

	'stash' : function () {
		try {
			const OpenILS=new Components.Constructor("@mozilla.org/openils_data_cache;1", "nsIOpenILS");
			var data_cache=new OpenILS( );
			data_cache.wrappedJSObject.OpenILS.prototype.data = {
				'list' : js2JSON( JSON2js( this.list ) ),
				'hash' : js2JSON( JSON2js( this.hash ) )
			}
		} catch(E) {
			this.error.sdump('D_ERROR','Error in OpenILS.data.stash(): ' + js2JSON(E) );
		}
	},

	'_fm_objects' : {

		'pgt' : [ 'open-ils.actor', 'open-ils.actor.groups.retrieve', [], true ],
		'cit' : [ 'open-ils.actor', 'open-ils.actor.user.ident_types.retrieve', [], true ],
		'cst' : [ 'open-ils.actor', 'open-ils.actor.standings.retrieve', [], true ],
		'acpl' : [ 'open-ils.search', 'open-ils.search.config.copy_location.retrieve.all', [], true ],
		'ccs' : [ 'open-ils.search', 'open-ils.search.config.copy_status.retrieve.all', [], true ],
		'aou' : [ 'open-ils.actor', 'open-ils.actor.org_tree.retrieve', [], true ],
		'aout' : [ 'open-ils.actor', 'open-ils.actor.org_types.retrieve', [], true ]	
	}

}

dump('exiting OpenILS/data.js\n');
