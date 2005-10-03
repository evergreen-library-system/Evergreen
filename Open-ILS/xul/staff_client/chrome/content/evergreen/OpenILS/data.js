dump('entering OpenILS/data.js\n');

if (typeof OpenILS == 'undefined') OpenILS = {};
OpenILS.data = function (mw,G) {

	this.mw = mw; this.G = G;

	var obj = this;

	this.chain = [];

	this.chain.push(
		function() {
			try {
				obj.au = obj.G.network.request(
					'open-ils.search',
					'open-ils.search.actor.user.session',
					[ obj.G.auth.session.key ]
				);
			} catch(E) {
				// what should we do?
			}
		}
	);

	function a_get(obj,i) { return [i, obj[i]]; }  // funkiness with loops and closures

	for (var i in this._cacheable_fm_objects) {
		var classname = a_get(this._cacheable_fm_objects,i)[0];
		var data = a_get(this._cacheable_fm_objects,i)[1];
		var app = data[0]; var method = data[1]; var params = data[2];
		this.chain.push(
			function() {
				try {
					obj.list[classname] = obj.G.network.request( app, method, params);
					// store an offline copy
				} catch(E) {
					// try offline
				}
				//obj.hash[classname] = convert_object_list_to_hash( obj.list[classname] );
			}
		);
	}

	/*
	var other_fm_objects = {
		'my_aou' : [ 
			'open-ils.actor', 
			'open-ils.actor.org_unit.full_path.retrieve', 
			[ obj.G.auth.session.key ] 
		],
		'my_actsc' : [ 
			'open-ils.circ', 
			'open-ils.circ.stat_cat.actor.retrieve.all', 
			[ obj.G.auth.session.key, obj.au.home_ou.id() ] 
		]
	}
	*/

	return this;
};

OpenILS.data.prototype = {

	'list' : {},
	'hash' : {},

	'init' : function () {

		if (typeof this.on_complete == 'function') {

			this.chain.push( this.on_complete );
		}

		JSAN.use('util.exec');
		util.exec.chain( this.chain );
	},

	'_cacheable_fm_objects' : {

		'pgt' : [ 'open-ils.actor', 'open-ils.actor.groups.retrieve', [] ],
		'cit' : [ 'open-ils.actor', 'open-ils.actor.user.ident_types.retrieve', [] ],
		'cst' : [ 'open-ils.actor', 'open-ils.actor.standings.retrieve', [] ],
		'acpl' : [ 'open-ils.search', 'open-ils.search.config.copy_location.retrieve.all', [] ],
		'ccs' : [ 'open-ils.search', 'open-ils.search.config.copy_status.retrieve.all', [] ],
		'aou' : [ 'open-ils.actor', 'open-ils.actor.org_tree.retrieve', [] ],
		'aout' : [ 'open-ils.actor', 'open-ils.actor.org_types.retrieve', [] ]	
	}

}

dump('exiting OpenILS/data.js\n');
