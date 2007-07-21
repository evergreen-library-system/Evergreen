dump('entering cat.record_buckets.js\n');

if (typeof cat == 'undefined') cat = {};
cat.record_buckets = function (params) {

	JSAN.use('util.error'); this.error = new util.error();
	JSAN.use('util.network'); this.network = new util.network();
	JSAN.use('util.date');
	JSAN.use('OpenILS.data'); this.data = new OpenILS.data(); this.data.init({'via':'stash'});
	this.first_pause = true;
}

cat.record_buckets.prototype = {
	'selection_list1' : [],
	'selection_list2' : [],
	'bucket_id_name_map' : {},

	'render_pending_records' : function() {
		if (this.first_pause) {
			this.first_pause = false;
		} else {
			alert("Action completed.");
		}
		var obj = this;
		obj.list1.clear();
		for (var i = 0; i < obj.record_ids.length; i++) {
			var item = obj.flesh_item_for_list( obj.record_ids[i] );
			if (item) obj.list1.append( item );
		}
	},

	'init' : function( params ) {

		var obj = this;

		obj.record_ids = params['record_ids'] || [];

		JSAN.use('circ.util');
		var columns = circ.util.columns( 
			{ 
				'title' : { 'hidden' : false },
				'author' : { 'hidden' : false },
				'edition' : { 'hidden' : false },
				'publisher' : { 'hidden' : false },
				'pubdate' : { 'hidden' : false },
				'isbn' : { 'hidden' : false },
				'tcn' : { 'hidden' : false },
			} 
		);

		JSAN.use('util.list'); 

		obj.list1 = new util.list('pending_records_list');
		obj.list1.init(
			{
				'columns' : columns,
				'map_row_to_columns' : circ.util.std_map_row_to_columns(),
				'on_select' : function(ev) {
					try {
						JSAN.use('util.functional');
						var sel = obj.list1.retrieve_selection();
						document.getElementById('clip_button1').disabled = sel.length < 1;
						obj.selection_list1 = util.functional.map_list(
							sel,
							function(o) { return JSON2js(o.getAttribute('retrieve_id')); }
						);
						obj.error.sdump('D_TRACE','circ/record_buckets: selection list 1 = ' + js2JSON(obj.selection_list1) );
						if (obj.selection_list1.length == 0) {
							obj.controller.view.record_buckets_sel_add.disabled = true;
						} else {
							obj.controller.view.record_buckets_sel_add.disabled = false;
						}
					} catch(E) {
						alert('FIXME: ' + E);
					}
				},

			}
		);

		obj.render_pending_records();
	
		obj.list2 = new util.list('records_in_bucket_list');
		obj.list2.init(
			{
				'columns' : columns,
				'map_row_to_columns' : circ.util.std_map_row_to_columns(),
				'on_select' : function(ev) {
					try {
						JSAN.use('util.functional');
						var sel = obj.list2.retrieve_selection();
						document.getElementById('clip_button2').disabled = sel.length < 1;
						obj.selection_list2 = util.functional.map_list(
							sel,
							function(o) { return JSON2js(o.getAttribute('retrieve_id')); }
						);
						obj.error.sdump('D_TRACE','circ/record_buckets: selection list 2 = ' + js2JSON(obj.selection_list2) );
						if (obj.selection_list2.length == 0) {
							obj.controller.view.record_buckets_delete_item.disabled = true;
							obj.controller.view.record_buckets_delete_item.setAttribute('disabled','true');
							obj.controller.view.record_buckets_export.disabled = true;
							obj.controller.view.record_buckets_export.setAttribute('disabled','true');
						} else {
							obj.controller.view.record_buckets_delete_item.disabled = false;
							obj.controller.view.record_buckets_delete_item.setAttribute('disabled','false');
							obj.controller.view.record_buckets_export.disabled = false;
							obj.controller.view.record_buckets_export.setAttribute('disabled','false');
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
					'save_columns2' : [
						['command'],
						function() { obj.list2.save_columns(); }
					],
					'save_columns1' : [
						['command'],
						function() { obj.list1.save_columns(); }
					],
					'sel_clip2' : [
						['command'],
						function() { obj.list2.clipboard(); }
					],
					'sel_clip1' : [
						['command'],
						function() { obj.list1.clipboard(); }
					],
					'record_buckets_menulist_placeholder' : [
						['render'],
						function(e) {
							return function() {
								JSAN.use('util.widgets'); JSAN.use('util.functional');
								var buckets = obj.network.simple_request(
									'BUCKET_RETRIEVE_VIA_USER',
									[ ses(), obj.data.list.au[0].id() ]
								);
								if (typeof buckets.ilsevent != 'undefined') {
									obj.error.standard_unexpected_error_alert('Could not retrieve your buckets.',buckets);
									return;
								}
								var items = [ ['Choose a bucket...',''], ['Retrieve shared bucket...',-1] ].concat(
									util.functional.map_list(
										util.functional.filter_list(
											buckets.biblio,
											function(o) {
												return o.btype() == 'staff_client';
											}
										),
										function(o) {
											obj.bucket_id_name_map[ o.id() ] = o.name();
											return [ o.name(), o.id() ];
										}
									).sort( 
				                        function( a, b ) {
				                            if (a[0] < b[0]) return -1;
				                            if (a[0] > b[0]) return 1;
				                            return 0;
				                        }
									)
								);
								obj.error.sdump('D_TRACE','items = ' + js2JSON(items));
								util.widgets.remove_children( e );
								var ml = util.widgets.make_menulist(
									items
								);
								e.appendChild( ml );
								ml.setAttribute('id','bucket_menulist');
								ml.setAttribute('accesskey','');

								function change_bucket(ev) {
									var bucket_id = ev.target.value;
									if (bucket_id < 0 ) {
										bucket_id = window.prompt('Enter bucket number:');
										ev.target.value = bucket_id;
										ev.target.setAttribute('value',bucket_id);
									}
									if (!bucket_id) return;
									var bucket = obj.network.simple_request(
										'BUCKET_FLESH',
										[ ses(), 'biblio', bucket_id ]
									);
									if (typeof bucket.ilsevent != 'undefined') {
										if (bucket.ilsevent == 1506 /* CONTAINER_NOT_FOUND */) {
											alert('Could not find a bucket with ID = ' + bucket_id);
										} else {
											obj.error.standard_unexpected_error_alert('Error retrieving bucket.  Did you use a valid bucket id?',bucket);
										}
										return;
									}
									try {
										var x = document.getElementById('info_box');
										x.setAttribute('hidden','false');
										x = document.getElementById('bucket_number');
										x.setAttribute('value',bucket.id());
										x = document.getElementById('bucket_name');
										x.setAttribute('value',bucket.name());
										x = document.getElementById('bucket_owner');
										var s = bucket.owner(); JSAN.use('patron.util');
										if (s && typeof s != "object") s = patron.util.retrieve_fleshed_au_via_id(ses(),s); 
										x.setAttribute('value',s.card().barcode() + " @ " + obj.data.hash.aou[ s.home_ou() ].shortname());
									} catch(E) {
										alert(E);
									}
									var items = bucket.items() || [];
									obj.list2.clear();
									for (var i = 0; i < items.length; i++) {
										var item = obj.flesh_item_for_list( 
											items[i].target_biblio_record_entry(),
											items[i].id()
										);
										if (item) obj.list2.append( item );
									}
								}

								ml.addEventListener( 'change_bucket', change_bucket , false);
								ml.addEventListener( 'command', function() {
									JSAN.use('util.widgets'); util.widgets.dispatch('change_bucket',ml);
								}, false);
								obj.controller.view.bucket_menulist = ml;
								JSAN.use('util.widgets'); util.widgets.dispatch('change_bucket',ml);
								document.getElementById('refresh').addEventListener( 'command', function() {
									JSAN.use('util.widgets'); util.widgets.dispatch('change_bucket',ml);
								}, false);
							};
						},
					],

					'record_buckets_add' : [
						['command'],
						function() {
							var bucket_id = obj.controller.view.bucket_menulist.value;
							if (!bucket_id) return;
							for (var i = 0; i < obj.record_ids.length; i++) {
								var bucket_item = new cbrebi();
								bucket_item.isnew('1');
								bucket_item.bucket(bucket_id);
								bucket_item.target_biblio_record_entry( obj.record_ids[i] );
								try {
									var robj = obj.network.simple_request('BUCKET_ITEM_CREATE',
										[ ses(), 'biblio', bucket_item ]);

									if (typeof robj == 'object') throw robj;

									var item = obj.flesh_item_for_list( obj.record_ids[i], robj );
									if (!item) continue;

									obj.list2.append( item );
								} catch(E) {
									alert( js2JSON(E) );
								}
							}
						}
					],
					'record_buckets_sel_add' : [
						['command'],
						function() {                                                        
							var bucket_id = obj.controller.view.bucket_menulist.value;
							if (!bucket_id) return;
							for (var i = 0; i < obj.selection_list1.length; i++) {
								var docid = obj.selection_list1[i].docid;
								var bucket_item = new cbrebi();
								bucket_item.isnew('1');
								bucket_item.bucket(bucket_id);
								bucket_item.target_biblio_record_entry( docid );
								try {
									var robj = obj.network.simple_request('BUCKET_ITEM_CREATE',
										[ ses(), 'biblio', bucket_item ]);

									if (typeof robj == 'object') throw robj;

									var item = obj.flesh_item_for_list( docid, robj );
									if (!item) continue;

									obj.list2.append( item );
								} catch(E) {
									alert( js2JSON(E) );
								}
							}

						}
					],
					'record_buckets_export' : [
						['command'],
						function() {                                                        
							for (var i = 0; i < obj.selection_list2.length; i++) {
								var docid = obj.selection_list2[i].docid;
								var item = obj.flesh_item_for_list( docid );
								if (item) {
									obj.list1.append( item );
									obj.record_ids.push( docid );
								}
							}
						}
					],

					'record_buckets_delete_item' : [
						['command'],
						function() {
							for (var i = 0; i < obj.selection_list2.length; i++) {
								try {
									var bucket_item_id = obj.selection_list2[i].bucket_item_id;
									var robj = obj.network.simple_request('BUCKET_ITEM_DELETE',
										[ ses(), 'biblio', bucket_item_id ]);
									if (typeof robj == 'object') throw robj;
								} catch(E) {
									alert(js2JSON(E));
								}
                                                        }
							alert("Action completed.");
							setTimeout(
								function() {
									JSAN.use('util.widgets'); 
									util.widgets.dispatch('change_bucket',obj.controller.view.bucket_menulist);
								}, 0
							);
						}
					],
					'record_buckets_delete_bucket' : [
						['command'],
						function() {
							try {
								var bucket = obj.controller.view.bucket_menulist.value;
								var name = obj.bucket_id_name_map[ bucket ];
								var conf = window.confirm('Delete the bucket named ' + name + '?');
								if (!conf) return;
								obj.list2.clear();
								var robj = obj.network.simple_request('BUCKET_DELETE',[ses(),'biblio',bucket]);
								if (typeof robj == 'object') throw robj;
								alert("Action completed.");
								obj.controller.render('record_buckets_menulist_placeholder');
								setTimeout(
									function() {
										JSAN.use('util.widgets'); 
										util.widgets.dispatch('change_bucket',obj.controller.view.bucket_menulist);
									}, 0
								);

							} catch(E) {
								alert('FIXME -- ' + E);
							}
						}
					],
					'record_buckets_new_bucket' : [
						['command'],
						function() {
							try {
								var name = prompt('What would you like to name the bucket?','','Bucket Creation');

								if (name) {
									var bucket = new cbreb();
									bucket.btype('staff_client');
									bucket.owner( obj.data.list.au[0].id() );
									bucket.name( name );

									var robj = obj.network.simple_request('BUCKET_CREATE',[ses(),'biblio',bucket]);

									if (typeof robj == 'object') {
										if (robj.ilsevent == 1710 /* CONTAINER_EXISTS */) {
											alert('You already have a bucket with that name.');
											return;
										}
										throw robj;
									}


									alert('Bucket "' + name + '" created.');

									obj.controller.render('record_buckets_menulist_placeholder');
									obj.controller.view.bucket_menulist.value = robj;
									setTimeout(
										function() {
											JSAN.use('util.widgets'); 
											util.widgets.dispatch('change_bucket',obj.controller.view.bucket_menulist);
										}, 0
									);
								}
							} catch(E) {
								alert( js2JSON(E) );
							}
						}
					],
					
					'cmd_record_buckets_export' : [
						['command'],
						function() {
							obj.list2.on_all_fleshed = function() {
								try {
									dump(obj.list2.dump_csv() + '\n');
									copy_to_clipboard(obj.list2.dump_csv());
									setTimeout(function(){obj.list2.on_all_fleshed = null;},0);
								} catch(E) {
									alert(E); 
								}
							}
							obj.list2.full_retrieve();
						}
					],

					'cmd_export1' : [
						['command'],
						function() {
							obj.list1.on_all_fleshed = function() {
								try {
									dump(obj.list1.dump_csv() + '\n');
									copy_to_clipboard(obj.list1.dump_csv());
									setTimeout(function(){obj.list1.on_all_fleshed = null;},0);
								} catch(E) {
									alert(E); 
								}
							}
							obj.list1.full_retrieve();
						}
					],

                    'cmd_print_export1' : [
                        ['command'],
                        function() {
                            try {
                                obj.list1.on_all_fleshed =
                                    function() {
                                        try {
                                            dump( obj.list1.dump_csv() + '\n' );
                                            //copy_to_clipboard(obj.list.dump_csv());
                                            JSAN.use('util.print'); var print = new util.print();
                                            print.simple(obj.list1.dump_csv(),{'content_type':'text/plain'});
                                            setTimeout(function(){ obj.list1.on_all_fleshed = null; },0);
                                        } catch(E) {
                                            obj.error.standard_unexpected_error_alert('print export',E);
                                        }
                                    }
                                obj.list1.full_retrieve();
                            } catch(E) {
                                obj.error.standard_unexpected_error_alert('print export',E);
                            }
                        }
                    ],


                    'cmd_print_export2' : [
                        ['command'],
                        function() {
                            try {
                                obj.list2.on_all_fleshed =
                                    function() {
                                        try {
                                            dump( obj.list2.dump_csv() + '\n' );
                                            //copy_to_clipboard(obj.list.dump_csv());
                                            JSAN.use('util.print'); var print = new util.print();
                                            print.simple(obj.list2.dump_csv(),{'content_type':'text/plain'});
                                            setTimeout(function(){ obj.list2.on_all_fleshed = null; },0);
                                        } catch(E) {
                                            obj.error.standard_unexpected_error_alert('print export',E);
                                        }
                                    }
                                obj.list2.full_retrieve();
                            } catch(E) {
                                obj.error.standard_unexpected_error_alert('print export',E);
                            }
                        }
                    ],

					'cmd_merge_records' : [
						['command'],
						function() {
							try {
								obj.list2.select_all();
								obj.data.stash_retrieve();
								JSAN.use('util.functional');

								var record_ids = util.functional.map_list(
									obj.list2.dump_retrieve_ids(),
									function (o) {
										return JSON2js(o).docid; // docid
									}
								);

								netscape.security.PrivilegeManager.enablePrivilege('UniversalXPConnect UniversalBrowserWrite');
								var top_xml = '<vbox xmlns="http://www.mozilla.org/keymaster/gatekeeper/there.is.only.xul" flex="1" >';
								top_xml += '<description>Merge these records? (Select the "lead" record first)</description>';
								top_xml += '<hbox><button id="lead" disabled="true" label="Merge" name="fancy_submit"/><button label="Cancel" accesskey="C" name="fancy_cancel"/></hbox></vbox>';

								var xml = '<form xmlns="http://www.w3.org/1999/xhtml">';
								xml += '<table><tr valign="top">';
								for (var i = 0; i < record_ids.length; i++) {
									xml += '<td><input value="Lead" id="record_' + record_ids[i] + '" type="radio" name="lead"';
									xml += ' onclick="' + "try { var x = document.getElementById('lead'); x.setAttribute('value',";
									xml += record_ids[i] + '); x.disabled = false; } catch(E) { alert(E); }">';
									xml += '</input>Lead Record? #' + record_ids[i] + '</td>';
								}
								xml += '</tr><tr valign="top">';
								for (var i = 0; i < record_ids.length; i++) {
									xml += '<td nowrap="nowrap"><iframe src="' + urls.XUL_BIB_BRIEF; 
									xml += '?docid=' + record_ids[i] + '"/></td>';
								}
								xml += '</tr><tr valign="top">';
								for (var i = 0; i < record_ids.length; i++) {
									html = obj.network.simple_request('MARC_HTML_RETRIEVE',[ record_ids[i] ]);
									xml += '<td nowrap="nowrap"><iframe style="min-height: 1000px; min-width: 300px;" flex="1" src="data:text/html,' + window.escape(html) + '"/></td>';
								}
								xml += '</tr></table></form>';
								//obj.data.temp_merge_top = top_xml; obj.data.stash('temp_merge_top');
								//obj.data.temp_merge_mid = xml; obj.data.stash('temp_merge_mid');
								JSAN.use('util.window'); var win = new util.window();
								var fancy_prompt_data = win.open(
									urls.XUL_FANCY_PROMPT,
									//+ '?xml_in_stash=temp_merge_mid'
									//+ '&top_xml_in_stash=temp_merge_top'
									//+ '&title=' + window.escape('Record Merging'),
									'fancy_prompt', 'chrome,resizable,modal,width=700,height=500',
									{
										'top_xml' : top_xml, 'xml' : xml, 'title' : 'Record Merging'
									}
								);
								//obj.data.stash_retrieve();

								if (typeof fancy_prompt_data.fancy_status == 'undefined' || fancy_prompt_data.fancy_status == 'incomplete') { alert('Merge Aborted'); return; }
								var robj = obj.network.simple_request('MERGE_RECORDS', 
									[ 
										ses(), 
										fancy_prompt_data.lead, 
										util.functional.filter_list( record_ids,
											function(o) {
												return o != fancy_prompt_data.lead;
											}
										)
									]
								);
								if (typeof robj.ilsevent != 'undefined') {
									throw(robj);
								} else {
									alert('Records were successfully merged.');
								}

								obj.render_pending_records(); // FIXME -- need a generic refresh for lists
								setTimeout(
									function() {
										JSAN.use('util.widgets'); 
										util.widgets.dispatch('change_bucket',obj.controller.view.bucket_menulist);
									}, 0
								);
							} catch(E) {
								obj.error.standard_unexpected_error_alert('Records were not likely merged.',E);
							}

						}
					],
					
					'cmd_delete_records' : [
						['command'],
						function() {
							try {
								obj.list2.select_all();
								obj.data.stash_retrieve();
								JSAN.use('util.functional');

								var record_ids = util.functional.map_list(
									obj.list2.dump_retrieve_ids(),
									function (o) {
										return JSON2js(o).docid; // docid
									}
								);

								netscape.security.PrivilegeManager.enablePrivilege('UniversalXPConnect UniversalBrowserWrite');
								var top_xml = '<vbox xmlns="http://www.mozilla.org/keymaster/gatekeeper/there.is.only.xul" flex="1" >';
								top_xml += '<description>Delete these records?</description>';
								top_xml += '<hbox><button id="lead" disabled="false" label="Delete" name="fancy_submit"/><button label="Cancel" accesskey="C" name="fancy_cancel"/></hbox></vbox>';

								var xml = '<form xmlns="http://www.w3.org/1999/xhtml">';
								xml += '<table><tr valign="top">';
								for (var i = 0; i < record_ids.length; i++) {
									xml += '<td>Record #' + record_ids[i] + '</td>';
								}
								xml += '</tr><tr valign="top">';
								for (var i = 0; i < record_ids.length; i++) {
									xml += '<td nowrap="nowrap"><iframe src="' + urls.XUL_BIB_BRIEF; 
									xml += '?docid=' + record_ids[i] + '"/></td>';
								}
								xml += '</tr><tr valign="top">';
								for (var i = 0; i < record_ids.length; i++) {
									html = obj.network.simple_request('MARC_HTML_RETRIEVE',[ record_ids[i] ]);
									xml += '<td nowrap="nowrap"><iframe style="min-height: 1000px; min-width: 300px;" flex="1" src="data:text/html,' + window.escape(html) + '"/></td>';
								}
								xml += '</tr></table></form>';
								//obj.data.temp_merge_top = top_xml; obj.data.stash('temp_merge_top');
								//obj.data.temp_merge_mid = xml; obj.data.stash('temp_merge_mid');
								JSAN.use('util.window'); var win = new util.window();
								var fancy_prompt_data = win.open(
									urls.XUL_FANCY_PROMPT,
									//+ '?xml_in_stash=temp_merge_mid'
									//+ '&top_xml_in_stash=temp_merge_top'
									//+ '&title=' + window.escape('Record Purging'),
									'fancy_prompt', 'chrome,resizable,modal,width=700,height=500',
									{
										'top_xml' : top_xml, 'xml' : xml, 'title' : 'Record Purging'
									}
								);
								//obj.data.stash_retrieve();
								if (typeof fancy_prompt_data.fancy_status == 'undefined' || fancy_prompt_data.fancy_status != 'complete') { alert('Delete Aborted'); return; }
								var s = '';
								for (var i = 0; i < record_ids.length; i++) {
									var robj = obj.network.simple_request('FM_BRE_DELETE',[ses(),record_ids[i]]);
									if (typeof robj.ilsevent != 'undefined') {
										if (!s) s = 'Error deleting these records:\n';
										s += 'Record #' + record_ids[i] + ' : ' + robj.textcode + ' : ' + robj.desc + '\n';
									}
								}
								if (s) { alert(s); } else { alert('Records deleted.'); }

								obj.render_pending_records(); // FIXME -- need a generic refresh for lists
								setTimeout(
									function() {
										JSAN.use('util.widgets'); 
										util.widgets.dispatch('change_bucket',obj.controller.view.bucket_menulist);
									}, 0
								);
							} catch(E) {
								obj.error.standard_unexpected_error_alert('Records were not likely deleted.',E);
							}

						}
					],

					'cmd_broken' : [
						['command'],
						function() { alert('Not Yet Implemented'); }
					],
					'cmd_record_buckets_done' : [
						['command'],
						function() {
							window.close();
						}
					],
					'cmd_sel_opac' : [
						['command'],
						function() {
							try {
								obj.list2.select_all();
								JSAN.use('util.functional');
								var docids = util.functional.map_list(
									obj.list2.dump_retrieve_ids(),
									function (o) {
										return JSON2js(o).docid; // docid
									}
								);
								for (var i = 0; i < docids.length; i++) {
									var doc_id = docids[i];
									var opac_url = xulG.url_prefix( urls.opac_rdetail ) + '?r=' + doc_id;
									var content_params = { 
										'session' : ses(),
										'authtime' : ses('authtime'),
										'opac_url' : opac_url,
									};
									xulG.new_tab(
										xulG.url_prefix(urls.XUL_OPAC_WRAPPER), 
										{'tab_name':'Retrieving title...'}, 
										content_params
									);
								}
							} catch(E) {
								obj.error.standard_unexpected_error_alert('Showing in OPAC',E);
							}
						}
					],

				}
			}
		);
		this.controller.render();

		if (typeof xulG == 'undefined') {
			obj.controller.view.cmd_sel_opac.disabled = true;
			obj.controller.view.cmd_sel_opac.setAttribute('disabled',true);
		} else {
			obj.controller.view.cmd_record_buckets_done.disabled = true;
			obj.controller.view.cmd_record_buckets_done.setAttribute('disabled',true);
		}
	},

	'flesh_item_for_list' : function(docid,bucket_item_id) {
		var obj = this;
		try {
			var record = obj.network.simple_request( 'MODS_SLIM_RECORD_RETRIEVE', [ docid ]);
			if (record == null || typeof(record.ilsevent) != 'undefined') {
				throw(record);
			} else {
				var item = {
					'retrieve_id' : js2JSON( { 'docid' : docid, 'bucket_item_id' : bucket_item_id } ),
					'row' : {
						'my' : {
							'mvr' : record,
						}
					}
				};
				return item;
			}
		} catch(E) {
			obj.error.standard_unexpected_error_alert('Could not retrieve this record: ' + docid,E);
			return null;
		}

	},
	
}

dump('exiting cat.record_buckets.js\n');
