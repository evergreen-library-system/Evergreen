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

	'init' : function( params ) {

		try {
			netscape.security.PrivilegeManager.enablePrivilege("UniversalXPConnect");
			var obj = this;

			JSAN.use('OpenILS.data'); obj.data = new OpenILS.data(); obj.data.init({'via':'stash'});
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

		} catch(E) {
			this.error.sdump('D_ERROR','cat.copy_browser.init: ' + E + '\n');
		}
	},

	'show_my_libs' : function() {
		var obj = this;
		try {
			var org = obj.data.hash.aou[ obj.data.list.au[0].ws_ou() ];
			obj.show_libs( org );
		
			var p_org = obj.data.hash.aou[ org.parent_ou() ];
			if (p_org) {
				JSAN.use('util.exec'); var exec = new util.exec();
				var funcs = [];
				for (var i = 0; i < p_org.children().length; i++) {
					funcs.push(
						function(o) {
							return function() {
								obj.show_libs( o );
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

	'show_libs' : function(start_aou) {
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
							obj.append_org(o,p,{'container':'true'}); 
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
						//x.setAttribute('open','true');
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

	'on_select' : function(list) {
		var obj = this;
		for (var i = 0; i < list.length; i++) {
			var node = obj.map_tree[ list[i] ];
			//if (node.lastChild.nodeName == 'treechildren') { continue; } else { alert(node.lastChild.nodeName); }
			var row_type = list[i].split('_')[0];
			var id = list[i].split('_')[1];
			switch(row_type) {
				case 'aou' : obj.on_select_org(id); break;
				default: alert('on_select: list[i] = ' + list[i] + ' row_type = ' + row_type + ' id = ' + id); break;
			}
		}
	},

	'on_select_org' : function(org_id) {
		var obj = this;
		var org = obj.data.hash.aou[ org_id ];
		var node = obj.map_tree[ 'org_' + org_id ];
		if (org.children()) {
			var funcs = [];
			for (var i = 0; i < org.children().length; i++) {
				funcs.push(
					function(o,p) {
						return function() {
							obj.append_org(o,p)
						}
					}(org.children()[i],org)
				);
			}
			JSAN.use('util.exec'); var exec = new util.exec();
			exec.chain( funcs );
		} else {
			alert('No Children');
		}
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
				'retrieve_id' : 'aou_' + org.id(),
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
					'on_click' : function(ev) {
						netscape.security.PrivilegeManager.enablePrivilege('UniversalXPConnect UniversalBrowserRead');
						var row = {}; var col = {}; var nobj = {};
						obj.list.node.treeBoxObject.getCellAt(ev.clientX,ev.clientY,row,col,nobj);
						if ((row.value == -1)||(nobj.value != 'twisty')) { return; }
						var node = obj.list.node.contentView.getItemAtIndex(row.value);
						var list = [ node.getAttribute('retrieve_id') ];
						if (typeof obj.on_select == 'function') {
							obj.on_select(list);
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
		}
	},
}

dump('exiting cat.copy_browser.js\n');
