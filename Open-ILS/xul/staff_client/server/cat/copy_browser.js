dump('entering cat.copy_browser.js\n');

if (typeof cat == 'undefined') cat = {};
cat.copy_browser = function (params) {
	try {
		netscape.security.PrivilegeManager.enablePrivilege("UniversalXPConnect");
		JSAN.use('util.error'); this.error = new util.error();
	} catch(E) {
		dump('cat.copy_browser: ' + E + '\n');
	}
}

cat.copy_browser.prototype = {

	'init' : function( params ) {

		try {
			netscape.security.PrivilegeManager.enablePrivilege("UniversalXPConnect");
			var obj = this;

			JSAN.use('util.controller'); obj.controller = new util.controller();
			obj.controller.init(
				{
					control_map : {
						'cmd_broken' : [
							['command'],
							function() { alert('Not Yet Implemented'); }
						],
						'cmd_test' : [
							['command'],
							function() { obj.test(); }
						],
					}
				}
			);

			obj.list_init(params);

		} catch(E) {
			this.error.sdump('D_ERROR','cat.copy_browser.init: ' + E + '\n');
		}
	},

	'test' : function() {
		var obj = this;
		try {
			JSAN.use('OpenILS.data'); obj.data = new OpenILS.data(); obj.data.init({'via':'stash'});
			JSAN.use('util.functional'); JSAN.use('util.exec'); var exec = new util.exec();

			obj.list.clear();

			var funcs = [];

			obj.map_tree = {};

			var start_at_this_aou;
			start_at_this_aou = obj.data.tree.aou;
			/*
			start_at_this_aou = obj.data.hash.aou[ obj.data.list.au[0].ws_ou() ];
			if (start_at_this_aou.parent_ou()) start_at_this_aou = obj.data.hash.aou[ start_at_this_aou.parent_ou() ];
			*/

			util.functional.walk_tree_preorder(
				start_at_this_aou,
				function (org) { dump('finding children for ' + org.shortname() + '\n'); return org.children(); },
				function (org,parent_org) {
					dump('queueing ' + org.shortname() + '\n');
					funcs.push(
						function() {
							try {
								var data = {
									'row' : {
										'my' : {
											'aou' : org,
										}
									},
									'render_cols' : [ 0, 1, 2 ]
								};
								if ( obj.data.hash.aout[ org.ou_type() ].can_have_vols() ) {
									data.row.my.volume_count = '??';
									data.row.my.copy_count = '??';
								} else {
									data.row.my.volume_count = '';
									data.row.my.copy_count = '';
								}
								if (parent_org) {
									data.node = obj.map_tree[ 'aou_' + parent_org.id() ];
								}
								obj.map_tree[ 'aou_' + org.id() ] = obj.list.append(data);
								if (parent_org) {
									if ( obj.data.hash.aou[ obj.data.list.au[0].ws_ou() ].parent_ou() == parent_org.id() ) data.node.setAttribute('open','true');
								} else {
									obj.map_tree[ 'aou_' + org.id() ].setAttribute('open','true');
								}
							} catch(E) {
								dump(E+'\n');
								alert(E);
							}
						}
					);
				}
			);

			exec.chain(funcs);

		} catch(E) {
			alert(E);
		}
	},

	'list_init' : function( params ) {

		try {
			netscape.security.PrivilegeManager.enablePrivilege("UniversalXPConnect");
			var obj = this;

			JSAN.use('circ.util');
			var columns = [
				{
					'id' : 'tree_location', 'label' : 'Location/Barcode', 'flex' : 1,
					'primary' : true, 'hidden' : false, 
					'render' : 'my.acp ? my.acp.barcode() : my.acn ? my.acn.label() : my.aou ? my.aou.name() : "???"'
				},
				{
					'id' : 'volume_count', 'label' : 'Volumes', 'flex' : 0,
					'primary' : false, 'hidden' : false, 
					'render' : 'my.volume_count'
				},
				{
					'id' : 'copy_count', 'label' : 'Copies', 'flex' : 0,
					'primary' : false, 'hidden' : false, 
					'render' : 'my.copy_count'
				},
			].concat(
				circ.util.columns( 
					{ 
						'location' : { 'hidden' : false },
						'circ_lib' : { 'hidden' : false },
						'owning_lib' : { 'hidden' : false },
						'call_number' : { 'hidden' : false },
					} 
				)
			);

			JSAN.use('util.list'); obj.list = new util.list('copy_tree');
			obj.list.init(
				{
					'columns' : columns,
					'map_row_to_column' : circ.util.std_map_row_to_column(' '),
					'retrieve_row' : function(params) {

						var row = params.row;

						var funcs = [];
					/*	
						if (!row.my.mvr) funcs.push(
							function() {

								row.my.mvr = obj.network.request(
									api.MODS_SLIM_RECORD_RETRIEVE_VIA_COPY.app,
									api.MODS_SLIM_RECORD_RETRIEVE_VIA_COPY.method,
									[ row.my.circ.target_copy() ]
								);

							}
						);
						if (!row.my.acp) {
							funcs.push(	
								function() {

									row.my.acp = obj.network.request(
										api.FM_ACP_RETRIEVE.app,
										api.FM_ACP_RETRIEVE.method,
										[ row.my.circ.target_copy() ]
									);

									params.row_node.setAttribute( 'retrieve_id',row.my.acp.barcode() );

								}
							);
						} else {
							params.row_node.setAttribute( 'retrieve_id',row.my.acp.barcode() );
						}
					*/
						funcs.push(
							function() {

								if (typeof params.on_retrieve == 'function') {
									params.on_retrieve(row);
								}

							}
						);

						JSAN.use('util.exec'); var exec = new util.exec();
						exec.on_error = function(E) {
							//var err = 'items chain: ' + js2JSON(E);
							//obj.error.sdump('D_ERROR',err);
							return true; /* keep going */
						}
						exec.chain( funcs );

						return row;
					},
					'on_select' : function(ev) {
						JSAN.use('util.functional');
						var sel = obj.list.retrieve_selection();
						var list = util.functional.map_list(
							sel,
							function(o) { return o.getAttribute('retrieve_id'); }
						);
						if (typeof obj.on_select == 'function') {
							obj.on_select(list);
						}
						if (typeof window.xulG == 'object' && typeof window.xulG.on_select == 'function') {
							window.xulG.on_select(list);
						}
					},
				}
			);
	

		} catch(E) {
			this.error.sdump('D_ERROR','cat.copy_browser.list_init: ' + E + '\n');
		}
	},
}

dump('exiting cat.copy_browser.js\n');
