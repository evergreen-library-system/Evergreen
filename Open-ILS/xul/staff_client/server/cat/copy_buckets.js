dump('entering cat.copy_buckets.js\n');

if (typeof cat == 'undefined') cat = {};
cat.copy_buckets = function (params) {

	JSAN.use('util.error'); this.error = new util.error();
	JSAN.use('util.network'); this.network = new util.network();
	JSAN.use('util.date');
	JSAN.use('OpenILS.data'); this.data = new OpenILS.data(); this.data.init({'via':'stash'});
}

cat.copy_buckets.prototype = {
	'selection_list' : [],

	'init' : function( params ) {

		var obj = this;

		obj.session = params['session'];
		obj.copy_ids = params['copy_ids'];

		JSAN.use('circ.util');
		var columns = circ.util.columns( 
			{ 
				'barcode' : { 'hidden' : false },
				'title' : { 'hidden' : false },
				'location' : { 'hidden' : false },
				'call_number' : { 'hidden' : false },
				'status' : { 'hidden' : false },
			} 
		);

		JSAN.use('util.list'); 

		obj.list1 = new util.list('pending_copies_list');
		obj.list1.init(
			{
				'columns' : columns,
				'map_row_to_column' : circ.util.std_map_row_to_column(),
			}
		);
		for (var i = 0; i < obj.copy_ids.length; i++) {
			var item = obj.flesh_item_for_list( obj.copy_ids[i] );
			if (item) obj.list1.append( item );
		}
		
		obj.list2 = new util.list('copies_in_bucket_list');
		obj.list2.init(
			{
				'columns' : columns,
				'map_row_to_column' : circ.util.std_map_row_to_column(),
				'on_select' : function(ev) {
					try {
						JSAN.use('util.functional');
						var sel = obj.list2.retrieve_selection();
						obj.selection_list = util.functional.map_list(
							sel,
							function(o) { return JSON2js(o.getAttribute('retrieve_id')); }
						);
						obj.error.sdump('D_TRACE','circ/copy_buckets: selection list = ' + js2JSON(obj.selection_list) );
						if (obj.selection_list.length == 0) {
							obj.controller.view.copy_buckets_delete_item.disabled = true;
						} else {
							obj.controller.view.copy_buckets_delete_item.disabled = false;
						}
					} catch(E) {
						alert('FIXME: ' + E);
					}
				},
			}
		);
		
		JSAN.use('util.controller'); obj.controller = new util.controller();
		obj.controller.init(
			{
				'control_map' : {
					'copy_buckets_menulist_placeholder' : [
						['render'],
						function(e) {
							return function() {
								JSAN.use('util.widgets'); JSAN.use('util.functional');
								var items = util.functional.map_list(
									obj.network.simple_request(
										'BUCKET_RETRIEVE_VIA_USER',
										[ obj.session, obj.data.list.au[0].id() ]
									).copy,
									function(o) {
										return [ o.name(), o.id() ];
									}
								);
								g.error.sdump('D_TRACE','items = ' + js2JSON(items));
								util.widgets.remove_children( e );
								var ml = util.widgets.make_menulist(
									items
								);
								e.appendChild( ml );
								ml.setAttribute('id','bucket_menulist');
								ml.setAttribute('accesskey','');
								ml.addEventListener(
									'command',
									function(ev) {
										alert(ev.target.value)
									}, false
								);
								obj.controller.view.bucket_menulist = ml;
							};
						},
					],

					'copy_buckets_add' : [
						['command'],
						function() {
							for (var i = 0; i < obj.copy_ids.length; i++) {
								var item = obj.flesh_item_for_list( obj.copy_ids[i] );
								if (item) obj.list2.append( item );
							}
						}
					],
					'copy_buckets_delete_item' : [
						['command'],
						function() {
                                                        JSAN.use('circ.util');
                                                        for (var i = 0; i < obj.selection_list.length; i++) {
                                                                var acp_id = obj.selection_list[i][0];
                                                                var barcode = obj.selection_list[i][1];
                                                        }
						}
					],
					'copy_buckets_delete_bucket' : [
						['command'],
						function() {
						}
					],
					'copy_buckets_new_bucket' : [
						['command'],
						function() {
							try {
								obj.data.new_bucket_value = ''; obj.data.stash('new_bucket_value');
								JSAN.use('util.window'); var win = new util.window();
								win.open(
									obj.data.server + urls.XUL_BUCKET_NAME,
									'new_bucket_win' + win.window_name_increment(),
									'chrome,resizable,modal,center'
								);

								obj.data.stash_retrieve();
								var name = obj.data.new_bucket_value;

								if (name) {
									var bucket = new ccb();
									bucket.btype('staff_client');
									bucket.owner( obj.data.list.au[0].id() );
									bucket.name( name );

									obj.network.simple_request('BUCKET_CREATE',[obj.session,'copy',bucket]);

									obj.controller.render('copy_buckets_menulist_placeholder');
								}
							} catch(E) {
								alert('FIXME -- ' + E);
							}
						}
					],
					'cmd_broken' : [
						['command'],
						function() { alert('Not Yet Implemented'); }
					],
					'cmd_copy_buckets_print' : [
						['command'],
						function() {
							dump( js2JSON( obj.list2.dump() ) );
							alert( js2JSON( obj.list2.dump() ) );
						}
					],
					'cmd_copy_buckets_reprint' : [
						['command'],
						function() {
						}
					],
					'cmd_copy_buckets_done' : [
						['command'],
						function() {
							window.close();
						}
					],
				}
			}
		);
		this.controller.render();

	},

	'flesh_item_for_list' : function(acp_id) {
		var obj = this;
		try {
			JSAN.use('circ.util');
			var copy = obj.network.simple_request( 'FM_ACP_RETRIEVE', [ acp_id ]);
			if (copy == null) {
				throw('COPY NOT FOUND');
			} else {
				var item = {
					'retrieve_id' : js2JSON( [ copy.id(), copy.barcode() ] ),
					'row' : {
						'my' : {
							'mvr' : obj.network.simple_request('MODS_SLIM_RECORD_RETRIEVE_VIA_COPY', [ copy.id() ]),
							'acp' : copy,
						}
					}
				};
				return item;
			}
		} catch(E) {
			alert('FIXME: need special alert and error handling\n' + js2JSON(E));
			return null;
		}

	},
	
}

dump('exiting cat.copy_buckets.js\n');
