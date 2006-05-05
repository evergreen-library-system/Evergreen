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

	'map_tree' : {},
	'map_acn' : {},
	'map_acp' : {},

	'init' : function( params ) {

		try {
			netscape.security.PrivilegeManager.enablePrivilege("UniversalXPConnect");
			var obj = this;

			obj.docid = params.docid;

			JSAN.use('util.network'); obj.network = new util.network();
			JSAN.use('OpenILS.data'); obj.data = new OpenILS.data(); obj.data.init({'via':'stash'});
			JSAN.use('util.controller'); obj.controller = new util.controller();
			obj.controller.init(
				{
					control_map : {
						'cmd_broken' : [
							['command'],
							function() { alert('Not Yet Implemented'); }
						],
						'cmd_show_my_libs' : [
							['command'],
							function() { 
								obj.show_my_libs(); 
							}
						],
						'cmd_show_all_libs' : [
							['command'],
							function() {
								obj.show_all_libs();
							}
						],
						'cmd_show_libs_with_copies' : [
							['command'],
							function() {
								obj.show_libs_with_copies();
							}
						],
						'cmd_clear' : [
							['command'],
							function() {
								obj.map_tree = {};
								obj.list.clear();
							}
						],
					}
				}
			);

			obj.list_init(params);

			obj.org_ids = obj.network.simple_request('FM_AOU_IDS_RETRIEVE_VIA_RECORD_ID',[ obj.docid ]);

			var org = obj.data.hash.aou[ obj.data.list.au[0].ws_ou() ];
			obj.show_libs( org );

		} catch(E) {
			this.error.sdump('D_ERROR','cat.copy_browser.init: ' + E + '\n');
		}
	},

	'show_my_libs' : function() {
		var obj = this;
		try {
			var org = obj.data.hash.aou[ obj.data.list.au[0].ws_ou() ];
			obj.show_libs( org, true );
		
			var p_org = obj.data.hash.aou[ org.parent_ou() ];
			if (p_org) {
				JSAN.use('util.exec'); var exec = new util.exec();
				var funcs = [];
				for (var i = 0; i < p_org.children().length; i++) {
					funcs.push(
						function(o) {
							return function() {
								obj.show_libs( o, true );
							}
						}( p_org.children()[i] )
					);
				}
				exec.chain( funcs );
			}
		} catch(E) {
			alert(E);
		}
	},

	'show_all_libs' : function() {
		var obj = this;
		try {
			obj.show_my_libs();

			obj.show_libs( obj.data.tree.aou );

			JSAN.use('util.exec'); var exec = new util.exec();
			var funcs = [];
			for (var i = 0; i < obj.data.tree.aou.children().length; i++) {
				funcs.push(
					function(o) {
						return function() {
							obj.show_libs( o );
						}
					}( obj.data.tree.aou.children()[i] )
				);
			}
			exec.chain( funcs );
		} catch(E) {
			alert(E);
		}
	},

	'show_libs_with_copies' : function() {
		var obj = this;
		try {
			JSAN.use('util.exec'); var exec = new util.exec();
			JSAN.use('util.functional');

			var orgs = util.functional.map_list(
				obj.org_ids,
				function(id) { return obj.data.hash.aou[id]; }
			).sort(
				function( a, b ) {
					if (a.shortname() < b.shortname()) return -1;
					if (a.shortname() > b.shortname()) return 1;
					return 0;
				}
			);
			var funcs = [];
			for (var i = 0; i < orgs.length; i++) {
				funcs.push(
					function(o) {
						return function() {
							obj.show_libs(o,true);
						}
					}( orgs[i] )
				);
			}
			exec.chain( funcs );
		} catch(E) {
			alert(E);
		}
	},

	'show_libs' : function(start_aou,show_open) {
		var obj = this;
		try {
			if (!start_aou) throw('show_libs: Need a start_aou');
			JSAN.use('OpenILS.data'); obj.data = new OpenILS.data(); obj.data.init({'via':'stash'});
			JSAN.use('util.functional'); JSAN.use('util.exec'); var exec = new util.exec();

			var funcs = [];

			var parents = [];
			var temp_aou = start_aou;
			while ( temp_aou.parent_ou() ) {
				temp_aou = obj.data.hash.aou[ temp_aou.parent_ou() ];
				parents.push( temp_aou );
			}
			parents.reverse();

			for (var i = 0; i < parents.length; i++) {
				funcs.push(
					function(o,p) {
						return function() { 
							if (show_open) {
								obj.append_org(o,p,{'container':'true','open':'true'}); 
							} else {
								obj.append_org(o,p,{'container':'true'}); 
							}
						};
					}(parents[i], obj.data.hash.aou[ parents[i].parent_ou() ])
				);
			}

			funcs.push(
				function(o,p) {
					return function() { obj.append_org(o,p); };
				}(start_aou,obj.data.hash.aou[ start_aou.parent_ou() ])
			);

			funcs.push(
				function() {
					if (start_aou.children()) {
						var x = obj.map_tree[ 'aou_' + start_aou.id() ];
						x.setAttribute('container','true');
						if (show_open) x.setAttribute('open','true');
						for (var i = 0; i < start_aou.children().length; i++) {
							funcs.push(
								function(o,p) {
									return function() { obj.append_org(o,p); };
								}( start_aou.children()[i], start_aou )
							);
						}
					}
				}
			);

			exec.chain( funcs );

		} catch(E) {
			alert(E);
		}
	},

	'on_select' : function(list,twisty) {
		var obj = this;
		for (var i = 0; i < list.length; i++) {
			var node = obj.map_tree[ list[i] ];
			//if (node.lastChild.nodeName == 'treechildren') { continue; } else { alert(node.lastChild.nodeName); }
			var row_type = list[i].split('_')[0];
			var id = list[i].split('_')[1];
			switch(row_type) {
				case 'aou' : obj.on_select_org(id,twisty); break;
				case 'acn' : obj.on_select_acn(id,twisty); break;
				default: break;
			}
		}
	},

	'on_select_acn' : function(acn_id,twisty) {
		var obj = this;
		try {
			var acn_tree = obj.map_acp[ 'acn_' + acn_id ];
			var funcs = [];
			if (acn_tree.copies()) {
				for (var i = 0; i < acn_tree.copies().length; i++) {
					funcs.push(
						function(c,a) {
							return function() {
								obj.append_acp(c,a);
							}
						}( acn_tree.copies()[i], acn_tree )
					)
				}
			}
			JSAN.use('util.exec'); var exec = new util.exec();
			exec.chain( funcs );
		} catch(E) {
			alert(E);
		}
	},

	'on_select_org' : function(org_id,twisty) {
		var obj = this;
		var org = obj.data.hash.aou[ org_id ];
		var funcs = [];
		if (org.children()) {
			for (var i = 0; i < org.children().length; i++) {
				funcs.push(
					function(o,p) {
						return function() {
							obj.append_org(o,p)
						}
					}(org.children()[i],org)
				);
			}
		} 
		if (obj.map_acn[ 'aou_' + org_id ]) {
			for (var i = 0; i < obj.map_acn[ 'aou_' + org_id ].length; i++) {
				funcs.push(
					function(o,a) {
						return function() {
							obj.append_acn(o,a);
						}
					}( org, obj.map_acn[ 'aou_' + org_id ][i] )
				);
			}
		}
		JSAN.use('util.exec'); var exec = new util.exec();
		exec.chain( funcs );
	},

	'append_org' : function (org,parent_org,params) {
		var obj = this;
		try {
			if (obj.map_tree[ 'aou_' + org.id() ]) {
				var x = obj.map_tree[ 'aou_' + org.id() ];
				if (params) {
					for (var i in params) {
						x.setAttribute(i,params[i]);
					}
				}
				return x;
			}

			var data = {
				'row' : {
					'my' : {
						'aou' : org,
					}
				},
				'skip_all_columns_except' : [0,1,2],
				'retrieve_id' : 'aou_' + org.id(),
			};
		
			var acn_tree_list;
			if ( obj.org_ids.indexOf( org.id() ) == -1 ) {
				if ( obj.data.hash.aout[ org.ou_type() ].can_have_vols() ) {
					data.row.my.volume_count = '0';
					data.row.my.copy_count = '<0>';
				} else {
					data.row.my.volume_count = '';
					data.row.my.copy_count = '';
				}
			} else {
				var v_count = 0; var c_count = 0;
				acn_tree_list = obj.network.simple_request(
					'FM_ACN_TREE_LIST_RETRIEVE_VIA_RECORD_ID_AND_ORG_IDS',
					[ ses(), obj.docid, [ org.id() ] ]
				);
				for (var i = 0; i < acn_tree_list.length; i++) {
					v_count++;
					if (acn_tree_list[i].copies()) c_count += acn_tree_list[i].copies().length;
				}
				data.row.my.volume_count = v_count;
				data.row.my.copy_count = '<' + c_count + '>';
			}
			if (parent_org) {
				data.node = obj.map_tree[ 'aou_' + parent_org.id() ];
			}

			var node = obj.list.append(data);
			if (params) {
				for (var i in params) {
					node.setAttribute(i,params[i]);
				}
			}
			obj.map_tree[ 'aou_' + org.id() ] = node;

			if (org.children()) {
				node.setAttribute('container','true');
			}

			if (parent_org) {
				if ( obj.data.hash.aou[ obj.data.list.au[0].ws_ou() ].parent_ou() == parent_org.id() ) {
					data.node.setAttribute('open','true');
				}
			} else {
				obj.map_tree[ 'aou_' + org.id() ].setAttribute('open','true');
			}

			if (acn_tree_list) {
				obj.map_acn[ 'aou_' + org.id() ] = acn_tree_list;
				node.setAttribute('container','true');
			}

		} catch(E) {
			dump(E+'\n');
			alert(E);
		}
	},

	'append_acn' : function( org, acn_tree, params ) {
		var obj = this;
		try {
			if (obj.map_tree[ 'acn_' + acn_tree.id() ]) {
				var x = obj.map_tree[ 'acn_' + acn_tree.id() ];
				if (params) {
					for (var i in params) {
						x.setAttribute(i,params[i]);
					}
				}
				return x;
			}

			var parent_node = obj.map_tree[ 'aou_' + org.id() ];
			var data = {
				'row' : {
					'my' : {
						'aou' : org,
						'acn' : acn_tree,
						'volume_count' : '',
						'copy_count' : acn_tree.copies() ? acn_tree.copies().length : '0',
					}
				},
				'skip_all_columns_except' : [0,1,2],
				'retrieve_id' : 'acn_' + acn_tree.id(),
				'node' : parent_node,
			};
			var node = obj.list.append(data);
			obj.map_tree[ 'acn_' + acn_tree.id() ] =  node;
			if (params) {
				for (var i in params) {
					node.setAttribute(i,params[i]);
				}
			}
			if (acn_tree.copies()) {
				obj.map_acp[ 'acn_' + acn_tree.id() ] = acn_tree;
				node.setAttribute('container','true');
			}

		} catch(E) {
			dump(E+'\n');
			alert(E);
		}
	},

	'append_acp' : function( acp_item, acn_tree, params ) {
		var obj = this;
		try {
			if (obj.map_tree[ 'acp_' + acp_item.id() ]) {
				var x = obj.map_tree[ 'acp_' + acp_item.id() ];
				if (params) {
					for (var i in params) {
						x.setAttribute(i,params[i]);
					}
				}
				return x;
			}

			var parent_node = obj.map_tree[ 'acn_' + acn_tree.id() ];
			var data = {
				'row' : {
					'my' : {
						'aou' : obj.data.hash.aou[ acn_tree.owning_lib() ],
						'acn' : acn_tree,
						'acp' : acp_item,
						'volume_count' : '',
						'copy_count' : '',
					}
				},
				'retrieve_id' : 'acp_' + acp_item.id(),
				'node' : parent_node,
			};
			var node = obj.list.append(data);
			obj.map_tree[ 'acp_' + acp_item.id() ] =  node;
			if (params) {
				for (var i in params) {
					node.setAttribute(i,params[i]);
				}
			}

		} catch(E) {
			dump(E+'\n');
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
					'render' : 'my.acp ? my.acp.barcode() : my.acn ? my.acn.label() : my.aou ? my.aou.shortname() + " : " + my.aou.name() : "???"'
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
						'status' : { 'hidden' : false },
					},
					{
						'just_these' : [
							'owning_lib',
							'circ_lib',
							'call_number',
							'copy_number',
							'location',
							'barcode',
							'loan_duration',
							'fine_level',
							'circulate',
							'holdable',
							'opac_visible',
							'ref',
							'deposit',
							'deposit_amount',
							'price',
							'circ_as_type',
							'circ_modifier',
							'status',
							'alert_message',
							'acp_id',
						]
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
							var err = 'items chain: ' + js2JSON(E);
							obj.error.sdump('D_ERROR',err);
							return true; /* keep going */
						}
						exec.chain( funcs );

						return row;
					},
					'on_click' : function(ev) {
						netscape.security.PrivilegeManager.enablePrivilege('UniversalXPConnect UniversalBrowserRead');
						var row = {}; var col = {}; var nobj = {};
						obj.list.node.treeBoxObject.getCellAt(ev.clientX,ev.clientY,row,col,nobj);
						if ((row.value == -1)||(nobj.value != 'twisty')) { return; }
						var node = obj.list.node.contentView.getItemAtIndex(row.value);
						var list = [ node.getAttribute('retrieve_id') ];
						if (typeof obj.on_select == 'function') {
							obj.on_select(list,true);
						}
						if (typeof window.xulG == 'object' && typeof window.xulG.on_select == 'function') {
							window.xulG.on_select(list);
						}
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
			alert(E);
		}
	},
}

dump('exiting cat.copy_browser.js\n');
