// vim:noet:sw=4:ts=4
var g = {};
g.map_acn = {};

var xulG = {};

function $(id) { return document.getElementById(id); }

function my_init() {
	try {
		/******************************************************************************************************/
		/* setup JSAN and some initial libraries */

		netscape.security.PrivilegeManager.enablePrivilege("UniversalXPConnect");
		if (typeof JSAN == 'undefined') {
			throw( $('commonStrings').getString('common.jsan.missing') );
		}
		JSAN.errorLevel = "die"; // none, warn, or die
		JSAN.addRepository('/xul/server/');
		JSAN.use('util.error'); g.error = new util.error();
		g.error.sdump('D_TRACE','my_init() for cat/copy_editor.xul');

		JSAN.use('util.functional');
		JSAN.use('OpenILS.data'); g.data = new OpenILS.data(); g.data.init({'via':'stash'});
		JSAN.use('util.network'); g.network = new util.network();

		g.docid = xul_param('docid',{'modal_xulG':true});
		g.handle_update = xul_param('handle_update',{'modal_xulG':true});

		/******************************************************************************************************/
		/* Get the copy ids from various sources and flesh them */

		var copy_ids = xul_param('copy_ids',{'concat':true,'JSON2js_if_cgi':true,'JSON2js_if_xulG':true,'JSON2js_if_xpcom':true,'stash_name':'temp_copy_ids','clear_xpcom':true,'modal_xulG':true});
		if (!copy_ids) copy_ids = [];

		if (copy_ids.length > 0) g.copies = g.network.simple_request(
			'FM_ACP_FLESHED_BATCH_RETRIEVE.authoritative',
			[ copy_ids ]
		);

		/******************************************************************************************************/
		/* And other fleshed copies if any */

		if (!g.copies) g.copies = [];
		var c = xul_param('copies',{'concat':true,'JSON2js_if_cgi':true,'JSON2js_if_xpcom':true,'stash_name':'temp_copies','clear_xpcom':true,'modal_xulG':true})
		if (c) g.copies = g.copies.concat(c);

		/******************************************************************************************************/
		/* We try to retrieve callnumbers for existing copies, but for new copies, we rely on this */

		g.callnumbers = xul_param('callnumbers',{'concat':true,'JSON2js_if_cgi':true,'JSON2js_if_xpcom':true,'stash_name':'temp_callnumbers','clear_xpcom':true,'modal_xulG':true});


		/******************************************************************************************************/
		/* Quick fix, this was defined inline in the global scope but now needs g.error and g.copies from my_init */
		/* Quick fix, messagecatalog only usable during/after onload */

        init_panes0();
        init_panes();

		/******************************************************************************************************/
		/* Is the interface an editor or a viewer, single or multi copy, existing copies or new copies? */

		if (xul_param('edit',{'modal_xulG':true}) == '1') { 

            // Editor desired, but let's check permissions
			g.edit = false;

            try {
                var check = g.network.simple_request(
                    'PERM_MULTI_ORG_CHECK',
                    [ 
                        ses(), 
                        g.data.list.au[0].id(), 
                        util.functional.map_list(
                            g.copies,
                            function (o) {
                                var lib;
                                var cn_id = o.call_number();
                                if (cn_id == -1) {
                                    lib = o.circ_lib(); // base perms on circ_lib instead of owning_lib if pre-cat
                                } else {
                                    if (! g.map_acn[ cn_id ]) {
                                        var req = g.network.simple_request('FM_ACN_RETRIEVE.authoritative',[ cn_id ]);
                                        if (typeof req.ilsevent == 'undefined') {
                                            g.map_acn[ cn_id ] = req;
                                            lib = g.map_acn[ cn_id ].owning_lib();
                                        } else {
                                            lib = o.circ_lib();
                                        }
                                    } else {
                                        lib = g.map_acn[ cn_id ].owning_lib();
                                    }
                                }
                                return typeof lib == 'object' ? lib.id() : lib;
                            }
                        ),
                        g.copies.length == 1 ? [ 'UPDATE_COPY' ] : [ 'UPDATE_COPY', 'UPDATE_BATCH_COPY' ]
                    ]
                );
                g.edit = check.length == 0;
            } catch(E) {
                g.error.standard_unexpected_error_alert('batch permission check',E);
            }

			if (g.edit) {
                $('caption').setAttribute('label', $('catStrings').getString('staff.cat.copy_editor.caption')); 
    			$('save').setAttribute('hidden','false'); 
    			g.retrieve_templates();
            } else {
			    $('top_nav').setAttribute('hidden','true');
            }
		} else {
			$('top_nav').setAttribute('hidden','true');
		}

		if (g.copies.length > 0 && g.copies[0].id() < 0) {
			document.getElementById('copy_notes').setAttribute('hidden','true');
			g.apply("status",5 /* In Process */);
			$('save').setAttribute('label', $('catStrings').getString('staff.cat.copy_editor.create_copies'));
		} else {
			g.panes_and_field_names.left_pane = 
				[
					[
						$('catStrings').getString('staff.cat.copy_editor.status'),
						{ 
							render: 'typeof fm.status() == "object" ? fm.status().name() : g.data.hash.ccs[ fm.status() ].name()', 
							input: g.safe_to_edit_copy_status() ? 'c = function(v){ g.apply("status",v); if (typeof post_c == "function") post_c(v); }; x = util.widgets.make_menulist( util.functional.map_list( g.data.list.ccs, function(obj) { return [ obj.name(), obj.id(), typeof my_constants.magical_statuses[obj.id()] != "undefined" ? true : false ]; } ).sort() ); x.addEventListener("apply",function(f){ return function(ev) { f(ev.target.value); } }(c), false);' : undefined,
							//input: 'c = function(v){ g.apply("status",v); if (typeof post_c == "function") post_c(v); }; x = util.widgets.make_menulist( util.functional.map_list( util.functional.filter_list( g.data.list.ccs, function(obj) { return typeof my_constants.magical_statuses[obj.id()] == "undefined"; } ), function(obj) { return [ obj.name(), obj.id() ]; } ).sort() ); x.addEventListener("apply",function(f){ return function(ev) { f(ev.target.value); } }(c), false);',
						}
					]
				].concat(g.panes_and_field_names.left_pane);
		}

		if (g.copies.length != 1) {
			document.getElementById('copy_notes').setAttribute('hidden','true');
		}

		/******************************************************************************************************/
		/* Show the Record Details? */

		if (g.docid) {
			document.getElementById('brief_display').setAttribute(
				'src',
				urls.XUL_BIB_BRIEF + '?docid=' + g.docid
			);
		} else {
			document.getElementById('brief_display').setAttribute('hidden','true');
		}

		/******************************************************************************************************/
		/* Add stat cats to the panes_and_field_names.right_pane4 */

        g.populate_stat_cats();

		/******************************************************************************************************/
		/* Backup copies :) */

		g.original_copies = js2JSON( g.copies );

		/******************************************************************************************************/
		/* Do it */

		g.summarize( g.copies );
		g.render();

	} catch(E) {
		var err_msg = $("commonStrings").getFormattedString('common.exception', ['cat/copy_editor.js', E]);
		try { g.error.sdump('D_ERROR',err_msg); } catch(E) { dump(err_msg); dump(js2JSON(E)); }
		alert(err_msg);
	}
}

/******************************************************************************************************/
/* Retrieve Templates */

g.retrieve_templates = function() {
	try {
		JSAN.use('util.widgets'); JSAN.use('util.functional');
		g.templates = {};
		var robj = g.network.simple_request('FM_AUS_RETRIEVE',[ses(),g.data.list.au[0].id()]);
		if (typeof robj['staff_client.copy_editor.templates'] != 'undefined') {
			g.templates = robj['staff_client.copy_editor.templates'];
		}
		util.widgets.remove_children('template_placeholder');
		var list = util.functional.map_object_to_list( g.templates, function(obj,i) { return [i, i]; } );

		g.template_menu = util.widgets.make_menulist( list );
        g.template_menu.setAttribute('id','template_menu');
		$('template_placeholder').appendChild(g.template_menu);
        g.template_menu.addEventListener(
            'command',
            function() { g.copy_editor_prefs[ 'template_menu' ] = { 'value' : g.template_menu.value }; g.save_attributes(); },
            false
        );
	} catch(E) {
		g.error.standard_unexpected_error_alert($('catStrings').getString('staff.cat.copy_editor.retrieve_templates.error'), E);
	}
}

/******************************************************************************************************/
/* Apply Template */

g.apply_template = function() {
	try {
		var name = g.template_menu.value;
		if (g.templates[ name ] != 'undefined') {
			var template = g.templates[ name ];
			for (var i in template) {
				g.changed[ i ] = template[ i ];
				switch( template[i].type ) {
					case 'attribute' :
						g.apply(template[i].field,template[i].value);
					break;
					case 'stat_cat' :
						if (g.stat_cat_seen[ template[i].field ]) g.apply_stat_cat(template[i].field,template[i].value);
					break;
					case 'owning_lib' :
						g.apply_owning_lib(template[i].value);
					break;
				}
			}
			g.summarize( g.copies );
			g.render();
		}
	} catch(E) {
		g.error.standard_unexpected_error_alert($('catStrings').getString('staff.cat.copy_editor.apply_templates.error'), E);
	}
}

/******************************************************************************************************/
/* Save as Template */

g.save_template = function() {
	try {
		var name = window.prompt(
			$('catStrings').getString('staff.cat.copy_editor.save_as_template.prompt'),
			'',
			$('catStrings').getString('staff.cat.copy_editor.save_as_template.title')
		);
		if (!name) return;
		g.templates[name] = g.changed;
		var robj = g.network.simple_request(
			'FM_AUS_UPDATE',[ses(),g.data.list.au[0].id(), { 'staff_client.copy_editor.templates' : g.templates }]
		);
		if (typeof robj.ilsevent != 'undefined') {
			throw(robj);
		} else {
			alert($('catStrings').getFormattedString('staff.cat.copy_editor.save_as_template.success', [name]));
			setTimeout(
				function() {
					try {
						g.retrieve_templates();
					} catch(E) {
						g.error.standard_unexpected_error_alert($('catStrings').getString('staff.cat.copy_editor.save_as_template.error'), E);
					}
				},0
			);
		}
	} catch(E) {
		g.error.standard_unexpected_error_alert($('catStrings').getString('staff.cat.copy_editor.save_as_template.error'), E);
	}
}

/******************************************************************************************************/
/* Delete Template */

g.delete_template = function() {
	try {
		var name = g.template_menu.value;
		if (!name) return;
		if (! window.confirm($('catStrings').getFormattedString('staff.cat.copy_editor.delete_template.confirm', [name]))) return;
		delete(g.templates[name]);
		var robj = g.network.simple_request(
			'FM_AUS_UPDATE',[ses(),g.data.list.au[0].id(), { 'staff_client.copy_editor.templates' : g.templates }]
		);
		if (typeof robj.ilsevent != 'undefined') {
			throw(robj);
		} else {
			alert($('catStrings').getFormattedString('staff.cat.copy_editor.delete_template.confirm', [name]));
			setTimeout(
				function() {
					try {
						g.retrieve_templates();
					} catch(E) {
						g.error.standard_unexpected_error_alert($('catStrings').getString('staff.cat.copy_editor.delete_template.error'), E);
					}
				},0
			);
		}
	} catch(E) {
		g.error.standard_unexpected_error_alert($('catStrings').getString('staff.cat.copy_editor.delete_template.error'), E);
	}
}

/******************************************************************************************************/
/* Export Templates */

g.export_templates = function() {
	try {
		netscape.security.PrivilegeManager.enablePrivilege("UniversalXPConnect");
		JSAN.use('util.file'); var f = new util.file('');
        f.export_file( { 'title' : $('catStrings').getString('staff.cat.copy_editor.export_templates.title'), 'data' : g.templates } );
	} catch(E) {
		g.error.standard_unexpected_error_alert($('catStrings').getString('staff.cat.copy_editor.export_templates.error'), E);
	}
}

/******************************************************************************************************/
/* Import Templates */

g.import_templates = function() {
	try {
		netscape.security.PrivilegeManager.enablePrivilege("UniversalXPConnect");
		JSAN.use('util.file'); var f = new util.file('');
        var temp = f.import_file( { 'title' : $('catStrings').getString('staff.cat.copy_editor.import_templates.title') } );
		if (temp) {
			for (var i in temp) {

				if (g.templates[i]) {

					var r = g.error.yns_alert(
						$('catStrings').getString('staff.cat.copy_editor.import_templates.replace.prompt') + '\n' + g.error.pretty_print( js2JSON( temp[i] ) ),
						$('catStrings').getFormattedString('staff.cat.copy_editor.import_templates.replace.title', [i]),
						$('catStrings').getString('staff.cat.copy_editor.import_templates.replace.yes'),
						$('catStrings').getString('staff.cat.copy_editor.import_templates.replace.no'),
						null,
						$('catStrings').getString('staff.cat.copy_editor.import_templates.replace.click_here')
					);

					if (r == 0 /* Yes */) g.templates[i] = temp[i];

				} else {

					g.templates[i] = temp[i];

				}

			}

			var r = g.error.yns_alert(
				$('catStrings').getString('staff.cat.copy_editor.import_templates.save.prompt'),
				$('catStrings').getFormattedString('staff.cat.copy_editor.import_templates.save.title'),
				$('catStrings').getString('staff.cat.copy_editor.import_templates.save.yes'),
				$('catStrings').getString('staff.cat.copy_editor.import_templates.save.no'),
				null,
				$('catStrings').getString('staff.cat.copy_editor.import_templates.save.click_here')
			);

			if (r == 0 /* Yes */) {
				var robj = g.network.simple_request(
					'FM_AUS_UPDATE',[ses(),g.data.list.au[0].id(), { 'staff_client.copy_editor.templates' : g.templates }]
				);
				if (typeof robj.ilsevent != 'undefined') {
					throw(robj);
				} else {
					alert($('catStrings').getString('staff.cat.copy_editor.import_templates.save.success'));
					setTimeout(
						function() {
							try {
								g.retrieve_templates();
							} catch(E) {
								g.error.standard_unexpected_error_alert($('catStrings').getString('staff.cat.copy_editor.import_templates.save.error'), E);
							}
						},0
					);
				}
			} else {
				util.widgets.remove_children('template_placeholder');
				var list = util.functional.map_object_to_list( g.templates, function(obj,i) { return [i, i]; } );
				g.template_menu = util.widgets.make_menulist( list );
				$('template_placeholder').appendChild(g.template_menu);
				alert($('catStrings').getString('staff.cat.copy_editor.import_templates.note'));
			}

		}
	} catch(E) {
		g.error.standard_unexpected_error_alert($('catStrings').getString('staff.cat.copy_editor.import_templates.error'), E);
	}
}


/******************************************************************************************************/
/* Restore backup copies */

g.reset = function() {
	g.changed = {};
	g.copies = JSON2js( g.original_copies );
	g.summarize( g.copies );
	g.render();
}

/******************************************************************************************************/
/* Apply a value to a specific field on all the copies being edited */

g.apply = function(field,value) {
	g.error.sdump('D_TRACE','applying field = <' + field + '>  value = <' + value + '>\n');
	if (value == '<HACK:KLUDGE:NULL>') value = null;
	if (field == 'alert_message') { value = value.replace(/^\W+$/g,''); }
	if (field == 'price' || field == 'deposit_amount') {
		if (value == '') { value = null; } else { JSAN.use('util.money'); value = util.money.sanitize( value ); }
	}
	for (var i = 0; i < g.copies.length; i++) {
		var copy = g.copies[i];
		try {
			copy[field]( value ); copy.ischanged('1');
		} catch(E) {
			alert(E);
		}
	}
}

/******************************************************************************************************/
/* Apply a stat cat entry to all the copies being edited.  An entry_id of < 0 signifies the stat cat is being removed. */

g.apply_stat_cat = function(sc_id,entry_id) {
	g.error.sdump('D_TRACE','sc_id = ' + sc_id + '  entry_id = ' + entry_id + '\n');
	for (var i = 0; i < g.copies.length; i++) {
		var copy = g.copies[i];
		try {
			copy.ischanged('1');
			var temp = copy.stat_cat_entries();
			if (!temp) temp = [];
			temp = util.functional.filter_list(
				temp,
				function (obj) {
					return (obj.stat_cat() != sc_id);
				}
			);
			if (entry_id > -1) temp.push( 
				util.functional.find_id_object_in_list( 
					g.data.hash.asc[sc_id].entries(), 
					entry_id
				)
			);
			copy.stat_cat_entries( temp );

		} catch(E) {
			g.error.standard_unexpected_error_alert('apply_stat_cat',E);
		}
	}
}

/******************************************************************************************************/
/* Apply an "owning lib" to all the copies being edited.  That is, change and auto-vivicating volumes */

g.apply_owning_lib = function(ou_id) {
	g.error.sdump('D_TRACE','ou_id = ' + ou_id + '\n');
	for (var i = 0; i < g.copies.length; i++) {
		var copy = g.copies[i];
		try {
			if (!g.map_acn[copy.call_number()]) {
				var volume = g.network.simple_request('FM_ACN_RETRIEVE.authoritative',[ copy.call_number() ]);
				if (typeof volume.ilsevent != 'undefined') {
					g.error.standard_unexpected_error_alert($('catStrings').getFormattedString('staff.cat.copy_editor.apply_owning_lib.undefined_volume.error', [copy.barcode()]), volume);
					continue;
				}
				g.map_acn[copy.call_number()] = volume;
			}
			var old_volume = g.map_acn[copy.call_number()];
			var acn_id = g.network.simple_request(
				'FM_ACN_FIND_OR_CREATE',
				[ses(),old_volume.label(),old_volume.record(),ou_id]
			);
			if (typeof acn_id.ilsevent != 'undefined') {
				g.error.standard_unexpected_error_alert($('catStrings').getFormattedString('staff.cat.copy_editor.apply_owning_lib.call_number.error', [copy.barcode()]), acn_id);
				continue;
			}
			copy.call_number(acn_id);
			copy.ischanged('1');
		} catch(E) {
			g.error.standard_unexpected_error_alert('apply_stat_cat',E);
		}
	}
}

/******************************************************************************************************/
/* This returns true if none of the copies being edited are pre-cats */

g.safe_to_change_owning_lib = function() {
	try {
		var safe = true;
		for (var i = 0; i < g.copies.length; i++) {
			var cn = g.copies[i].call_number();
			if (typeof cn == 'object') { cn = cn.id(); }
			if (cn == -1) { safe = false; }
		}
		return safe;
	} catch(E) {
        g.error.standard_unexpected_error_alert('safe_to_change_owning_lib?',E);
		return false;
	}
}

/******************************************************************************************************/
/* This returns true if none of the copies being edited have a magical status found in my_constants.magical_statuses */

g.safe_to_edit_copy_status = function() {
	try {
		var safe = true;
		for (var i = 0; i < g.copies.length; i++) {
			var status = g.copies[i].status(); if (typeof status == 'object') status = status.id();
			if (typeof my_constants.magical_statuses[ status ] != 'undefined') safe = false;
		}
		return safe;
	} catch(E) {
		g.error.standard_unexpected_error_alert('safe_to_edit_copy_status?',E);
		return false;
	}
}

/******************************************************************************************************/
/* This concats and uniques all the alert messages for use as the default value for a new alert message */

g.populate_alert_message_input = function(tb) {
	try {
		var seen = {}; var s = '';
		for (var i = 0; i < g.copies.length; i++) {
			var msg = g.copies[i].alert_message(); 
			if (msg) {
				if (typeof seen[msg] == 'undefined') {
					s += msg + '\n';
					seen[msg] = true;
				}
			}
		}
		tb.setAttribute('value',s);
	} catch(E) {
		g.error.standard_unexpected_error_alert('populate_alert_message_input',E);
	}
}

/***************************************************************************************************************/
/* This returns a list of acpl's appropriate for the copies being edited (and caches them in the global stash) */

g.get_acpl_list_for_lib = function(lib_id,but_only_these) {
    g.data.stash_retrieve();
    var label = 'acpl_list_for_lib_'+lib_id;
    if (typeof g.data[label] == 'undefined') {
        var robj = g.network.simple_request('FM_ACPL_RETRIEVE', [ lib_id ]); // This returns acpl's for all ancestors and descendants as well as the lib
        if (typeof robj.ilsevent != 'undefined') throw(robj);
        var temp_list = [];
        for (var j = 0; j < robj.length; j++) {
            var my_acpl = robj[j];
            if (typeof g.data.hash.acpl[ my_acpl.id() ] == 'undefined') {
                g.data.hash.acpl[ my_acpl.id() ] = my_acpl;
                g.data.list.acpl.push( my_acpl );
            }
            var only_this_lib = my_acpl.owning_lib(); if (!only_this_lib) continue;
            if (typeof only_this_lib == 'object') only_this_lib = only_this_lib.id();
            if (but_only_these.indexOf( String( only_this_lib ) ) != -1) { // This filters out some of the libraries (usually the descendants)
                temp_list.push( my_acpl );
            }
        }
        g.data[label] = temp_list; g.data.stash(label,'hash','list');
    }
    return g.data[label];
}

/******************************************************************************************************/
/* This returns a list of acpl's appropriate for the copies being edited */

g.get_acpl_list = function() {
	try {

		JSAN.use('util.functional');

        var my_acpls = {};

        /**************************************/
        /* get owning libs from call numbers */

		var owning_libs = {}; 
		for (var i = 0; i < g.copies.length; i++) {
            var callnumber = g.copies[i].call_number();
            if (!callnumber) continue;
			var cn_id = typeof callnumber == 'object' ? callnumber.id() : callnumber;
			if (cn_id > 0) {
				if (! g.map_acn[ cn_id ]) {
					var req = g.network.simple_request('FM_ACN_RETRIEVE.authoritative',[ cn_id ]);
                    if (typeof req.ilsevent == 'undefined') {
    					g.map_acn[ cn_id ] = req;
                    } else {
                        continue;
                    }
				}
                var consider_lib = g.map_acn[ cn_id ].owning_lib();
                if (!consider_lib) continue;
                owning_libs[ typeof consider_lib == 'object' ? consider_lib.id() : consider_lib ] = true;
			}
		}
		if (g.callnumbers) {
			for (var i in g.callnumbers) {
                var consider_lib = g.callnumbers[i].owning_lib;
                if (!consider_lib) continue;
                owning_libs[ typeof consider_lib == 'object' ? consider_lib.id() : consider_lib ] = true;
			}
		}

        /***************************************************************************************************/
        /* now find the first ancestor they all have in common, get the acpl's for it and higher ancestors */

		JSAN.use('util.fm_utils');
        var libs = []; for (var i in owning_libs) libs.push(i);
        if (libs.length > 0) {
            var ancestor = util.fm_utils.find_common_aou_ancestor( libs );
            if (typeof ancestor == 'object' && ancestor != null) ancestor = ancestor.id();

            if (ancestor) {
                var ancestors = util.fm_utils.find_common_aou_ancestors( libs );
                var acpl_list = g.get_acpl_list_for_lib(ancestor, ancestors);
                if (acpl_list) for (var i = 0; i < acpl_list.length; i++) {
                    if (acpl_list[i] != null) {
                        my_acpls[ typeof acpl_list[i] == 'object' ? acpl_list[i].id() : acpl_list[i] ] = true;
                    }
                }
            }
        }
        
        /*****************/
        /* get circ libs */

        var circ_libs = {};

        for (var i = 0; i < g.copies.length; i++) {
            var consider_lib = g.copies[i].circ_lib();
            if (!consider_lib) continue;
            circ_libs[ typeof consider_lib == 'object' ? consider_lib.id() : consider_lib ] = true;
        }

        /***************************************************************************************************/
        /* now find the first ancestor they all have in common, get the acpl's for it and higher ancestors */

        libs = []; for (var i in circ_libs) libs.push(i);
        if (libs.length > 0) {
    		var ancestor = util.fm_utils.find_common_aou_ancestor( libs );
    		if (typeof ancestor == 'object' && ancestor != null) ancestor = ancestor.id();

    		if (ancestor) {
    		    var ancestors = util.fm_utils.find_common_aou_ancestors( libs );
    			var acpl_list = g.get_acpl_list_for_lib(ancestor, ancestors);
                if (acpl_list) for (var i = 0; i < acpl_list.length; i++) {
                    if (acpl_list[i] != null) {
                        my_acpls[ typeof acpl_list[i] == 'object' ? acpl_list[i].id() : acpl_list[i] ] = true;
                    }
                }
            }
        }

        var acpl_list = []; for (var i in my_acpls) acpl_list.push( g.data.hash.acpl[ i ] );
        return acpl_list.sort(
            function(a,b) {
                var label_a = g.data.hash.aou[ a.owning_lib() ].shortname() + ' : ' + a.name();
                var label_b = g.data.hash.aou[ b.owning_lib() ].shortname() + ' : ' + b.name();
                if (label_a < label_b) return -1;
                if (label_a > label_b) return 1;
                return 0;
            }
        );
	
	} catch(E) {
		g.error.standard_unexpected_error_alert('get_acpl_list',E);
		return [];
	}
}


/******************************************************************************************************/
/* This keeps track of what fields have been edited for styling purposes */

g.changed = {};

/******************************************************************************************************/
/* These need data from the middle layer to render */

function init_panes0() {
g.special_exception = {};
g.special_exception[$('catStrings').getString('staff.cat.copy_editor.field.owning_library.label')] = function(label,value) {
		JSAN.use('util.widgets');
		if (value>0) { /* an existing call number */
			g.network.simple_request(
				'FM_ACN_RETRIEVE.authoritative',
				[ value ],
				function(req) {
					var cn = '??? id = ' + value;
					try {
						cn = req.getResultObject();
					} catch(E) {
						g.error.sdump('D_ERROR','callnumber retrieve: ' + E);
					}
					util.widgets.set_text(label,g.data.hash.aou[ cn.owning_lib() ].shortname() + ' : ' + cn.label());
				}
			);
		} else { /* a yet to be created call number */
			if (g.callnumbers) {
				util.widgets.set_text(label,g.data.hash.aou[ g.callnumbers[value].owning_lib ].shortname() + ' : ' + g.callnumbers[value].label);
			}
		}
	};
g.special_exception[$('catStrings').getString('staff.cat.copy_editor.field.creator.label')] = function(label,value) {
		if (value == null || value == '' || value == 'null') return;
		g.network.simple_request(
			'FM_AU_RETRIEVE_VIA_ID',
			[ ses(), value ],
			function(req) {
				var p = '??? id = ' + value;
				try {
					p = req.getResultObject();
					p = p.usrname();

				} catch(E) {
					g.error.sdump('D_ERROR','patron retrieve: ' + E);
				}
				JSAN.use('util.widgets');
				util.widgets.set_text(label,p);
			}
		);
	};
g.special_exception[$('catStrings').getString('staff.cat.copy_editor.field.last_editor.label')] = function(label,value) {
		if (value == null || value == '' || value == 'null') return;
		g.network.simple_request(
			'FM_AU_RETRIEVE_VIA_ID',
			[ ses(), value ],
			function(req) {
				var p = '??? id = ' + value;
				try {
					p = req.getResultObject();
					p = p.usrname();

				} catch(E) {
					g.error.sdump('D_ERROR','patron retrieve: ' + E);
				}
				util.widgets.set_text(label,p);
			}
		);
	};
}

/******************************************************************************************************/
g.readonly_stat_cat_names = [];
g.editable_stat_cat_names = [];

/******************************************************************************************************/
/* These get show in the left panel */

function init_panes() {
g.panes_and_field_names = {

	'left_pane' :
[
	[
		$('catStrings').getString('staff.cat.copy_editor.field.barcode.label'),
		{
			render: 'fm.barcode();',
		}
	], 
	[
		$('catStrings').getString('staff.cat.copy_editor.field.creation_date.label'),
		{ 
			render: 'util.date.formatted_date( fm.create_date(), "%F");',
		}
	],
	[
		$('catStrings').getString('staff.cat.copy_editor.field.creator.label'),
		{ 
			render: 'fm.creator();',
		}
	],
	[
		$('catStrings').getString('staff.cat.copy_editor.field.last_edit_date.label'),
		{ 
			render: 'util.date.formatted_date( fm.edit_date(), "%F");',
		}
	],
	[
		$('catStrings').getString('staff.cat.copy_editor.field.last_editor.label'),
		{
			render: 'fm.editor();',
		}
	],

],

'right_pane' :
[
	[
		$('catStrings').getString('staff.cat.copy_editor.field.location.label'),
		{ 
			render: 'typeof fm.location() == "object" ? fm.location().name() : g.data.lookup("acpl",fm.location()).name()', 
			input: 'c = function(v){ g.apply("location",v); if (typeof post_c == "function") post_c(v); }; x = util.widgets.make_menulist( util.functional.map_list( g.get_acpl_list(), function(obj) { return [ g.data.hash.aou[ obj.owning_lib() ].shortname() + " : " + obj.name(), obj.id() ]; }).sort()); x.addEventListener("apply",function(f){ return function(ev) { f(ev.target.value); } }(c), false);',

		}
	],
	[
		$('catStrings').getString('staff.cat.copy_editor.field.circulation_library.label'),
		{ 	
			render: 'typeof fm.circ_lib() == "object" ? fm.circ_lib().shortname() : g.data.hash.aou[ fm.circ_lib() ].shortname()',
			//input: 'c = function(v){ g.apply("circ_lib",v); if (typeof post_c == "function") post_c(v); }; x = util.widgets.make_menulist( util.functional.map_list( util.functional.filter_list(g.data.list.my_aou, function(obj) { return g.data.hash.aout[ obj.ou_type() ].can_have_vols(); }), function(obj) { return [ obj.shortname(), obj.id() ]; }).sort() ); x.addEventListener("apply",function(f){ return function(ev) { f(ev.target.value); } }(c), false);',
			input: 'c = function(v){ g.apply("circ_lib",v); if (typeof post_c == "function") post_c(v); }; x = util.widgets.make_menulist( util.functional.map_list( g.data.list.aou, function(obj) { var sname = obj.shortname(); for (i = sname.length; i < 20; i++) sname += " "; return [ obj.name() ? sname + " " + obj.name() : obj.shortname(), obj.id(), ( ! get_bool( g.data.hash.aout[ obj.ou_type() ].can_have_vols() ) ), ( g.data.hash.aout[ obj.ou_type() ].depth() * 2), ]; }), g.data.list.au[0].ws_ou()); x.addEventListener("apply",function(f){ return function(ev) { f(ev.target.value); } }(c), false);',
		} 
	],
	[
		$('catStrings').getString('staff.cat.copy_editor.field.owning_library.label'),
		{
			render: 'fm.call_number();',
			input: g.safe_to_change_owning_lib() ? 'c = function(v){ g.apply_owning_lib(v); if (typeof post_c == "function") post_c(v); }; x = util.widgets.make_menulist( util.functional.map_list( g.data.list.aou, function(obj) { var sname = obj.shortname(); for (i = sname.length; i < 20; i++) sname += " "; return [ obj.name() ? sname + " " + obj.name() : obj.shortname(), obj.id(), ( ! get_bool( g.data.hash.aout[ obj.ou_type() ].can_have_vols() ) ), ( g.data.hash.aout[ obj.ou_type() ].depth() * 2), ]; }), g.data.list.au[0].ws_ou()); x.addEventListener("apply",function(f){ return function(ev) { f(ev.target.value); } }(c), false);' : undefined,
		}
	],
	[
		$('catStrings').getString('staff.cat.copy_editor.field.copy_number.label'),
		{ 
			render: 'fm.copy_number() == null ? $("catStrings").getString("staff.cat.copy_editor.field.unset_or_null") : fm.copy_number()',
			input: 'c = function(v){ g.apply("copy_number",v); if (typeof post_c == "function") post_c(v); }; x = document.createElement("textbox"); x.addEventListener("apply",function(f){ return function(ev) { f(ev.target.value); } }(c), false);',
		}
	],


],

'right_pane2' :
[
	[
		$('catStrings').getString('staff.cat.copy_editor.field.circulate.label'),
		{ 	
			render: 'fm.circulate() == null ? $("catStrings").getString("staff.cat.copy_editor.field.unset_or_null") : ( get_bool( fm.circulate() ) ? $("catStrings").getString("staff.cat.copy_editor.field.circulate.yes_or_true") : $("catStrings").getString("staff.cat.copy_editor.field.circulate.no_or_false") )',
			input: 'c = function(v){ g.apply("circulate",v); if (typeof post_c == "function") post_c(v); }; x = util.widgets.make_menulist( [ [ $("catStrings").getString("staff.cat.copy_editor.field.circulate.yes_or_true"), get_db_true() ], [ $("catStrings").getString("staff.cat.copy_editor.field.circulate.no_or_false"), get_db_false() ] ] ); x.addEventListener("apply",function(f){ return function(ev) { f(ev.target.value); } }(c), false);',
		}
	],
	[
		$('catStrings').getString('staff.cat.copy_editor.field.holdable.label'),
		{ 
			render: 'fm.holdable() == null ? $("catStrings").getString("staff.cat.copy_editor.field.unset_or_null") : ( get_bool( fm.holdable() ) ? $("catStrings").getString("staff.cat.copy_editor.field.holdable.yes_or_true") : $("catStrings").getString("staff.cat.copy_editor.field.holdable.no_or_false") )',
			input: 'c = function(v){ g.apply("holdable",v); if (typeof post_c == "function") post_c(v); }; x = util.widgets.make_menulist( [ [ $("catStrings").getString("staff.cat.copy_editor.field.holdable.yes_or_true"), get_db_true() ], [ $("catStrings").getString("staff.cat.copy_editor.field.holdable.no_or_false"), get_db_false() ] ] ); x.addEventListener("apply",function(f){ return function(ev) { f(ev.target.value); } }(c), false);',
		}
	],
	[
		$('catStrings').getString('staff.cat.copy_editor.field.age_based_hold_protection.label'),
		{
			render: 'fm.age_protect() == null ? $("catStrings").getString("staff.cat.copy_editor.field.unset_or_null") : ( typeof fm.age_protect() == "object" ? fm.age_protect().name() : g.data.hash.crahp[ fm.age_protect() ].name() )', 
			input: 'c = function(v){ g.apply("age_protect",v); if (typeof post_c == "function") post_c(v); }; x = util.widgets.make_menulist( [ [ $("catStrings").getString("staff.cat.copy_editor.remove_age_based_hold_protection"), "<HACK:KLUDGE:NULL>" ] ].concat( util.functional.map_list( g.data.list.crahp, function(obj) { return [ obj.name(), obj.id() ]; }).sort() ) ); x.addEventListener("apply",function(f){ return function(ev) { f(ev.target.value); } }(c), false);',
		}

	],
	[
		$('catStrings').getString('staff.cat.copy_editor.field.loan_duration.label'),
		{ 
			render: 'switch(Number(fm.loan_duration())){ case 1: $("catStrings").getString("staff.cat.copy_editor.field.loan_duration.short"); break; case 2: $("catStrings").getString("staff.cat.copy_editor.field.loan_duration.normal"); break; case 3: $("catStrings").getString("staff.cat.copy_editor.field.loan_duration.extended"); break; }',
			input: 'c = function(v){ g.apply("loan_duration",v); if (typeof post_c == "function") post_c(v); }; x = util.widgets.make_menulist( [ [ $("catStrings").getString("staff.cat.copy_editor.field.loan_duration.short"), "1" ], [ $("catStrings").getString("staff.cat.copy_editor.field.loan_duration.normal"), "2" ], [ $("catStrings").getString("staff.cat.copy_editor.field.loan_duration.extended"), "3" ] ] ); x.addEventListener("apply",function(f){ return function(ev) { f(ev.target.value); } }(c), false);',

		}
	],
	[
		$('catStrings').getString('staff.cat.copy_editor.field.fine_level.label'),
		{
			render: 'switch(Number(fm.fine_level())){ case 1: $("catStrings").getString("staff.cat.copy_editor.field.fine_level.low"); break; case 2: $("catStrings").getString("staff.cat.copy_editor.field.fine_level.normal"); break; case 3: $("catStrings").getString("staff.cat.copy_editor.field.fine_level.high"); break; }',
			input: 'c = function(v){ g.apply("fine_level",v); if (typeof post_c == "function") post_c(v); }; x = util.widgets.make_menulist( [ [ $("catStrings").getString("staff.cat.copy_editor.field.fine_level.low"), "1" ], [ $("catStrings").getString("staff.cat.copy_editor.field.fine_level.normal"), "2" ], [ $("catStrings").getString("staff.cat.copy_editor.field.fine_level.high"), "3" ] ] ); x.addEventListener("apply",function(f){ return function(ev) { f(ev.target.value); } }(c), false);',
		}
	],

	 [
		$('catStrings').getString('staff.cat.copy_editor.field.circulate_as_type.label'),
		{ 	
			render: 'fm.circ_as_type() == null ? $("catStrings").getString("staff.cat.copy_editor.field.unset_or_null") : g.data.hash.citm[ fm.circ_as_type() ].value()',
			input: 'c = function(v){ g.apply("circ_as_type",v); if (typeof post_c == "function") post_c(v); }; x = util.widgets.make_menulist( [ [ $("catStrings").getString("staff.cat.copy_editor.remove_circulate_as_type"), "<HACK:KLUDGE:NULL>" ] ].concat( util.functional.map_list( g.data.list.citm, function(n){return [ n.code() + " - " + n.value(), n.code()];} ).sort() ) ); x.addEventListener("apply",function(f){ return function(ev) { f(ev.target.value); } }(c), false);',
		} 
	],
	[
		$('catStrings').getString('staff.cat.copy_editor.field.circulation_modifier.label'),
		{	
			render: 'fm.circ_modifier() == null ? $("catStrings").getString("staff.cat.copy_editor.field.unset_or_null") : fm.circ_modifier()',
			/*input: 'c = function(v){ g.apply("circ_modifier",v); if (typeof post_c == "function") post_c(v); }; x = document.createElement("textbox"); x.addEventListener("apply",function(f){ return function(ev) { f(ev.target.value); } }(c), false);',*/
			input: 'c = function(v){ g.apply("circ_modifier",v); if (typeof post_c == "function") post_c(v); }; x = util.widgets.make_menulist( util.functional.map_list( g.data.list.circ_modifier, function(obj) { return [ obj, obj ]; } ).sort() ); x.setAttribute("editable","true"); x.addEventListener("apply",function(f){ return function(ev) { f(ev.target.value); } }(c), false);',
		}
	],
],

'right_pane3' :
[	[
		$('catStrings').getString('staff.cat.copy_editor.field.alert_message.label'),
		{
			render: 'fm.alert_message() == null ? $("catStrings").getString("staff.cat.copy_editor.field.unset_or_null") : fm.alert_message()',
			input: 'c = function(v){ g.apply("alert_message",v); if (typeof post_c == "function") post_c(v); }; x = document.createElement("textbox"); x.setAttribute("multiline",true); g.populate_alert_message_input(x); x.addEventListener("apply",function(f){ return function(ev) { f( ev.target.value ); } }(c), false);',
		}
	],

	[
		$('catStrings').getString('staff.cat.copy_editor.field.deposit.label'),
		{ 
			render: 'fm.deposit() == null ? $("catStrings").getString("staff.cat.copy_editor.field.unset_or_null") : ( get_bool( fm.deposit() ) ? $("catStrings").getString("staff.cat.copy_editor.field.deposit.yes_or_true") : $("catStrings").getString("staff.cat.copy_editor.field.deposit.no_or_false") )',
			input: 'c = function(v){ g.apply("deposit",v); if (typeof post_c == "function") post_c(v); }; x = util.widgets.make_menulist( [ [ $("catStrings").getString("staff.cat.copy_editor.field.deposit.yes_or_true"), get_db_true() ], [ $("catStrings").getString("staff.cat.copy_editor.field.deposit.no_or_false"), get_db_false() ] ] ); x.addEventListener("apply",function(f){ return function(ev) { f(ev.target.value); } }(c), false);',
		}
	],
	[
		$('catStrings').getString('staff.cat.copy_editor.field.deposit_amount.label'),
		{ 
			render: 'if (fm.deposit_amount() == null) { $("catStrings").getString("staff.cat.copy_editor.field.unset_or_null"); } else { util.money.sanitize( fm.deposit_amount() ); }',
			input: 'c = function(v){ g.apply("deposit_amount",v); if (typeof post_c == "function") post_c(v); }; x = document.createElement("textbox"); x.addEventListener("apply",function(f){ return function(ev) { f(ev.target.value); } }(c), false);',
		}
	],
	[
		$('catStrings').getString('staff.cat.copy_editor.field.price.label'),
		{ 
			render: 'if (fm.price() == null) { $("catStrings").getString("staff.cat.copy_editor.field.unset_or_null"); } else { util.money.sanitize( fm.price() ); }', 
			input: 'c = function(v){ g.apply("price",v); if (typeof post_c == "function") post_c(v); }; x = document.createElement("textbox"); x.addEventListener("apply",function(f){ return function(ev) { f(ev.target.value); } }(c), false);',
		}
	],

	[
		$('catStrings').getString('staff.cat.copy_editor.field.opac_visible.label'),
		{ 
			render: 'fm.opac_visible() == null ? $("catStrings").getString("staff.cat.copy_editor.field.unset_or_null") : ( get_bool( fm.opac_visible() ) ? $("catStrings").getString("staff.cat.copy_editor.field.opac_visible.yes_or_true") : $("catStrings").getString("staff.cat.copy_editor.field.opac_visible.no_or_false") )', 
			input: 'c = function(v){ g.apply("opac_visible",v); if (typeof post_c == "function") post_c(v); }; x = util.widgets.make_menulist( [ [ $("catStrings").getString("staff.cat.copy_editor.field.opac_visible.yes_or_true"), get_db_true() ], [ $("catStrings").getString("staff.cat.copy_editor.field.opac_visible.no_or_false"), get_db_false() ] ] ); x.addEventListener("apply",function(f){ return function(ev) { f(ev.target.value); } }(c), false);',
		}
	],
	[
		$('catStrings').getString('staff.cat.copy_editor.field.reference.label'),
		{ 
			render: 'fm.ref() == null ? $("catStrings").getString("staff.cat.copy_editor.field.unset_or_null") : ( get_bool( fm.ref() ) ? $("catStrings").getString("staff.cat.copy_editor.field.reference.yes_or_true") : $("catStrings").getString("staff.cat.copy_editor.field.reference.no_or_false") )', 
			input: 'c = function(v){ g.apply("ref",v); if (typeof post_c == "function") post_c(v); }; x = util.widgets.make_menulist( [ [ $("catStrings").getString("staff.cat.copy_editor.field.reference.yes_or_true"), get_db_true() ], [ $("catStrings").getString("staff.cat.copy_editor.field.reference.no_or_false"), get_db_false() ] ] ); x.addEventListener("apply",function(f){ return function(ev) { f(ev.target.value); } }(c), false);',
		}
	],
],

'right_pane4' : 
[
]

};
}

/******************************************************************************************************/
/* This loops through all our fieldnames and all the copies, tallying up counts for the different values */

g.summarize = function( copies ) {
	/******************************************************************************************************/
	/* Setup */

	JSAN.use('util.date'); JSAN.use('util.money');
	g.summary = {};
	g.field_names = [];
	for (var i in g.panes_and_field_names) {
		g.field_names = g.field_names.concat( g.panes_and_field_names[i] );
	}
	g.field_names = g.field_names.concat( g.editable_stat_cat_names );
	g.field_names = g.field_names.concat( g.readonly_stat_cat_names );

	/******************************************************************************************************/
	/* Loop through the field names */

	for (var i = 0; i < g.field_names.length; i++) {

		var field_name = g.field_names[i][0];
		var render = g.field_names[i][1].render;
        var attr = g.field_names[i][1].attr;
		g.summary[ field_name ] = {};

		/******************************************************************************************************/
		/* Loop through the copies */

		for (var j = 0; j < copies.length; j++) {

			var fm = copies[j];
			var cmd = render || ('fm.' + field_name + '();');
			var value = '???';

			/**********************************************************************************************/
			/* Try to retrieve the value for this field for this copy */

			try { 
				value = eval( cmd ); 
			} catch(E) { 
				g.error.sdump('D_ERROR','Attempted ' + cmd + '\n' +  E + '\n'); 
			}
			if (typeof value == 'object' && value != null) {
				alert('FIXME: field_name = <' + field_name + '>  value = <' + js2JSON(value) + '>\n');
			}

			/**********************************************************************************************/
			/* Tally the count */

			if (g.summary[ field_name ][ value ]) {
				g.summary[ field_name ][ value ]++;
			} else {
				g.summary[ field_name ][ value ] = 1;
			}
		}
	}
	g.error.sdump('D_TRACE','summary = ' + js2JSON(g.summary) + '\n');
}

/******************************************************************************************************/
/* Display the summarized data and inputs for editing */

g.render = function() {

	/******************************************************************************************************/
	/* Library setup and clear any existing interface */

	JSAN.use('util.widgets'); JSAN.use('util.date'); JSAN.use('util.money'); JSAN.use('util.functional');

	for (var i in g.panes_and_field_names) {
		var p = document.getElementById(i);
		if (p) util.widgets.remove_children(p);
	}

	/******************************************************************************************************/
	/* Populate the library filter menu for stat cats */

    var sc_libs = {};
    for (var i = 0; i < g.panes_and_field_names.right_pane4.length; i++) {
        sc_libs[ g.panes_and_field_names.right_pane4[i][1].attr.sc_lib ] = true;
    }
    var sc_libs2 = [];
    for (var i in sc_libs) { sc_libs2.push( [ g.data.hash.aou[ i ].shortname(), i ] ); }
    sc_libs2.sort();
    var x = document.getElementById("stat_cat_lib_filter_menu").firstChild;
    JSAN.use('util.widgets'); util.widgets.remove_children(x);
    for (var i = 0; i < sc_libs2.length; i++) {
        var menuitem = document.createElement('menuitem');
        menuitem.setAttribute('id','filter_'+sc_libs2[i][1]);
        menuitem.setAttribute('type','checkbox');
        menuitem.setAttribute('checked','true');
        menuitem.setAttribute('label',sc_libs2[i][0]);
        menuitem.setAttribute('value',sc_libs2[i][1]);
        menuitem.setAttribute('oncommand','try{g.toggle_stat_cat_display(this);}catch(E){alert(E);}');
        x.appendChild(menuitem);
    }

	/******************************************************************************************************/
	/* Prepare the panes */

	var groupbox; var caption; var vbox; var grid; var rows;
	
	/******************************************************************************************************/
	/* Loop through the field names */

	for (h in g.panes_and_field_names) {
		if (!document.getElementById(h)) continue;
		for (var i = 0; i < g.panes_and_field_names[h].length; i++) {
			try {
				var f = g.panes_and_field_names[h][i]; var fn = f[0]; var attr = f[1].attr;
				groupbox = document.createElement('groupbox'); document.getElementById(h).appendChild(groupbox);
                if (attr) {
                    for (var a in attr) {
                        groupbox.setAttribute(a,attr[a]);
                    }
                }
				if (typeof g.changed[fn] != 'undefined') groupbox.setAttribute('class','copy_editor_field_changed');
				caption = document.createElement('caption'); groupbox.appendChild(caption);
				caption.setAttribute('label',fn); caption.setAttribute('id','caption_'+fn);
				vbox = document.createElement('vbox'); groupbox.appendChild(vbox);
				grid = util.widgets.make_grid( [ { 'flex' : 1 }, {}, {} ] ); vbox.appendChild(grid);
				grid.setAttribute('flex','1');
				rows = grid.lastChild;
				var row;
				
				/**************************************************************************************/
				/* Loop through each value for the field */

				for (var j in g.summary[fn]) {
					var value = j; var count = g.summary[fn][j];
					row = document.createElement('row'); rows.appendChild(row);
					var label1 = document.createElement('description'); row.appendChild(label1);
					if (g.special_exception[ fn ]) {
						g.special_exception[ fn ]( label1, value );
					} else {
						label1.appendChild( document.createTextNode(value) );
					}
					var label2 = document.createElement('description'); row.appendChild(label2);
					var copy_count;
					if (count == 1) {
						copy_count = $('catStrings').getString('staff.cat.copy_editor.copy_count');
					} else {
						copy_count = $('catStrings').getFormattedString('staff.cat.copy_editor.copy_count.plural', [count]);
					}
					label2.appendChild( document.createTextNode(copy_count) );
				}
				var hbox = document.createElement('hbox'); 
				hbox.setAttribute('id',fn);
				groupbox.appendChild(hbox);
				var hbox2 = document.createElement('hbox');
				groupbox.appendChild(hbox2);

				/**************************************************************************************/
				/* Render the input widget */

				if (f[1].input && g.edit) {
					g.render_input(hbox,f[1]);
				}

			} catch(E) {
				g.error.sdump('D_ERROR','copy editor: ' + E + '\n');
			}
		}
	}
    
    
	/******************************************************************************************************/
	/* Synchronize stat cat visibility with library filter menu, and default template selection */
    JSAN.use('util.file'); 
	var file = new util.file('copy_editor_prefs.'+g.data.server_unadorned);
	g.copy_editor_prefs = util.widgets.load_attributes(file);
    for (var i in g.copy_editor_prefs) {
        if (i.match(/filter_/) && g.copy_editor_prefs[i].checked == '') {
            try { 
                g.toggle_stat_cat_display( document.getElementById(i) ); 
            } catch(E) { alert(E); }
        }
    }
    if (g.template_menu) g.template_menu.value = g.template_menu.getAttribute('value');

}

/******************************************************************************************************/
/* This actually draws the change button and input widget for a given field */
g.render_input = function(node,blob) {
	try {
		// node = hbox ;    groupbox ->  hbox, hbox

		var groupbox = node.parentNode;
		var caption = groupbox.firstChild;
		var vbox = node.previousSibling;
		var hbox = node;
		var hbox2 = node.nextSibling;

		var input_cmd = blob.input;
		var render_cmd = blob.render;
        var attr = blob.attr;

		var block = false; var first = true;

		function on_mouseover(ev) {
			groupbox.setAttribute('style','background: white');
		}

		function on_mouseout(ev) {
			groupbox.setAttribute('style','');
		}

		vbox.addEventListener('mouseover',on_mouseover,false);
		vbox.addEventListener('mouseout',on_mouseout,false);
		groupbox.addEventListener('mouseover',on_mouseover,false);
		groupbox.addEventListener('mouseout',on_mouseout,false);
		groupbox.firstChild.addEventListener('mouseover',on_mouseover,false);
		groupbox.firstChild.addEventListener('mouseout',on_mouseout,false);

		function on_click(ev){
			try {
				if (block) return; block = true;

				function post_c(v) {
					try {
						/* FIXME - kludgy */
						var t = input_cmd.match('apply_stat_cat') ? 'stat_cat' : ( input_cmd.match('apply_owning_lib') ? 'owning_lib' : 'attribute' );
						var f;
						switch(t) {
							case 'attribute' :
								f = input_cmd.match(/apply\("(.+?)",/)[1];
							break;
							case 'stat_cat' :
								f = input_cmd.match(/apply_stat_cat\((.+?),/)[1];
							break;
							case 'owning_lib' :
								f = null;
							break;
						}
						g.changed[ hbox.id ] = { 'type' : t, 'field' : f, 'value' : v };
						block = false;
						setTimeout(
							function() {
								g.summarize( g.copies );
								g.render();
								document.getElementById(caption.id).focus();
							}, 0
						);
					} catch(E) {
						g.error.standard_unexpected_error_alert('post_c',E);
					}
				}
				var x; var c; eval( input_cmd );
				if (x) {
					util.widgets.remove_children(vbox);
					util.widgets.remove_children(hbox);
					util.widgets.remove_children(hbox2);
					hbox.appendChild(x);
					var apply = document.createElement('button');
					apply.setAttribute('label', $('catStrings').getString('staff.cat.copy_editor.apply.label'));
					apply.setAttribute('accesskey', $('catStrings').getString('staff.cat.copy_editor.apply.accesskey'));
					hbox2.appendChild(apply);
					apply.addEventListener('command',function() { c(x.value); },false);
					var cancel = document.createElement('button');
					cancel.setAttribute('label', $('catStrings').getString('staff.cat.copy_editor.cancel.label'));
					cancel.addEventListener('command',function() { setTimeout( function() { g.summarize( g.copies ); g.render(); document.getElementById(caption.id).focus(); }, 0); }, false);
					hbox2.appendChild(cancel);
					setTimeout( function() { x.focus(); }, 0 );
				}
			} catch(E) {
				g.error.standard_unexpected_error_alert('render_input',E);
			}
		}
		vbox.addEventListener('click',on_click, false);
		hbox.addEventListener('click',on_click, false);
		caption.addEventListener('click',on_click, false);
		caption.addEventListener('keypress',function(ev) {
			if (ev.keyCode == 13 /* enter */ || ev.keyCode == 77 /* mac enter */) on_click();
		}, false);
		caption.setAttribute('style','-moz-user-focus: normal');
		caption.setAttribute('onfocus','this.setAttribute("class","outline_me")');
		caption.setAttribute('onblur','this.setAttribute("class","")');

	} catch(E) {
		g.error.sdump('D_ERROR',E + '\n');
	}
}

/******************************************************************************************************/
/* store the copies in the global xpcom stash */

g.stash_and_close = function() {
	try {
		if (g.handle_update) {
			try {
				var r = g.network.request(
					api.FM_ACP_FLESHED_BATCH_UPDATE.app,
					api.FM_ACP_FLESHED_BATCH_UPDATE.method,
					[ ses(), g.copies, true ]
				);
				if (typeof r.ilsevent != 'undefined') {
					g.error.standard_unexpected_error_alert('copy update',r);
				} else {
					alert($('catStrings').getString('staff.cat.copy_editor.handle_update.success'));
				}
				/* FIXME -- revisit the return value here */
			} catch(E) {
				alert($('catStrings').getString('staff.cat.copy_editor.handle_update.error') + ' ' + js2JSON(E));
			}
		}
		//g.data.temp_copies = js2JSON( g.copies );
		//g.data.stash('temp_copies');
		xulG.copies = g.copies;
		update_modal_xulG(xulG);
		window.close();
	} catch(E) {
		g.error.standard_unexpected_error_alert('stash and close',E);
	}
}

/******************************************************************************************************/
/* spawn copy notes interface */

g.copy_notes = function() {
	JSAN.use('util.window'); var win = new util.window();
	win.open(
		urls.XUL_COPY_NOTES, 
		//+ '?copy_id=' + window.escape(g.copies[0].id()),
		$("catStrings").getString("staff.cat.copy_editor.copy_notes"),'chrome,resizable,modal',
		{ 'copy_id' : g.copies[0].id() }
	);
}

/******************************************************************************************************/
/* hides or unhides stat cats based on library stat cat filter menu */
g.toggle_stat_cat_display = function(el) {
    if (!el) return;
    var visible = el.getAttribute('checked');
    var nl = document.getElementsByAttribute('sc_lib',el.getAttribute('value'));
    for (var n = 0; n < nl.length; n++) {
        if (visible) {
            nl[n].setAttribute('hidden','false');
        } else {
            nl[n].setAttribute('hidden','true');
        }
    }
    g.copy_editor_prefs[ el.getAttribute('id') ] = { 'checked' : visible };
    g.save_attributes();
}

/******************************************************************************************************/
/* This adds a stat cat definition to the stat cat pane for rendering */
g.save_attributes = function() {
	JSAN.use('util.widgets'); JSAN.use('util.file'); var file = new util.file('copy_editor_prefs.'+g.data.server_unadorned);
    var what_to_save = {};
    for (var i in g.copy_editor_prefs) {
        what_to_save[i] = [];
        for (var j in g.copy_editor_prefs[i]) what_to_save[i].push(j);
    }
	util.widgets.save_attributes(file, what_to_save );
}

/******************************************************************************************************/
/* This adds a stat cat definition to the stat cat pane for rendering */
g.add_stat_cat = function(sc) {
    try {
		if (typeof g.data.hash.asc == 'undefined') { g.data.hash.asc = {}; g.data.stash('hash'); }

		var sc_id = sc;

		if (typeof sc == 'object') {

			sc_id = sc.id();
		}

		if (typeof g.stat_cat_seen[sc_id] != 'undefined') { return; }

		g.stat_cat_seen[ sc_id ] = 1;

		if (typeof sc != 'object') {

			sc = g.network.simple_request(
				'FM_ASC_BATCH_RETRIEVE',
				[ ses(), [ sc_id ] ]
			)[0];

		}

		g.data.hash.asc[ sc.id() ] = sc; g.data.stash('hash');

		var label_name = g.data.hash.aou[ sc.owner() ].shortname() + " : " + sc.name();

		var temp_array = [
			label_name,
			{
				render: 'var l = util.functional.find_list( fm.stat_cat_entries(), function(e){ return e.stat_cat() == ' 
					+ sc.id() + '; } ); l ? l.value() : $("catStrings").getString("staff.cat.copy_editor.field.unset_or_null");',
				input: 'c = function(v){ g.apply_stat_cat(' + sc.id() + ',v); if (typeof post_c == "function") post_c(v); }; x = util.widgets.make_menulist( [ [ $("catStrings").getString("staff.cat.copy_editor.remove_stat_cat_entry"), -1 ] ].concat( util.functional.map_list( g.data.hash.asc[' + sc.id() 
					+ '].entries(), function(obj){ return [ obj.value(), obj.id() ]; } ) ).sort() ); '
					+ 'x.addEventListener("apply",function(f){ return function(ev) { f(ev.target.value); } }(c),false);',
                attr: {
                    sc_lib: sc.owner(),
                }
			}
		];

		g.panes_and_field_names.right_pane4.push( temp_array );
	} catch(E) {
		g.error.standard_unexpected_error_alert($('catStrings').getString('staff.cat.copy_editor.add_stat_cat.error'), E);
    }
}

/******************************************************************************************************/
/* Add stat cats to the panes_and_field_names.right_pane4 */
g.populate_stat_cats = function() {
    try {
        g.data.stash_retrieve();
		g.stat_cat_seen = {};

		function get(lib_id,only_these) {
            g.data.stash_retrieve();
			var label = 'asc_list_for_lib_'+lib_id;
			if (typeof g.data[label] == 'undefined') {
				var robj = g.network.simple_request('FM_ASC_RETRIEVE_VIA_AOU', [ ses(), lib_id ]);
				if (typeof robj.ilsevent != 'undefined') throw(robj);
				var temp_list = [];
				for (var j = 0; j < robj.length; j++) {
					var my_asc = robj[j];
                    if (typeof g.data.hash.asc == 'undefined') { g.data.hash.asc = {}; }
					if (typeof g.data.hash.asc[ my_asc.id() ] == 'undefined') {
						g.data.hash.asc[ my_asc.id() ] = my_asc;
					}
                    var only_this_lib = my_asc.owner(); if (typeof only_this_lib == 'object') only_this_lib = only_this_lib.id();
					if (only_these.indexOf( String( only_this_lib ) ) != -1) {
						temp_list.push( my_asc );
					}
				}
				g.data[label] = temp_list; g.data.stash(label,'hash','list');
			}
			return g.data[label];
		}

		/* The stat cats for the pertinent library -- this is based on workstation ou */
        var label = 'asc_list_for_' + typeof g.data.ws_ou == 'object' ? g.data.ws_ou.id() : g.data.ws_ou;
        g.data[ label ] = g.data.list.my_asc; g.data.stash('label');
		for (var i = 0; i < g.data.list.my_asc.length; i++) {
			g.add_stat_cat( g.data.list.my_asc[i] );
		}

        /* For the others, we want to consider the owning libs, circ libs, and any libs that have stat cats already on the copies,
            however, if batch editing, we only want to show the ones they have in common.  So let's compile the libs  */

        function add_common_ancestors(sc_libs) {
            JSAN.use('util.fm_utils'); 
            var libs = []; for (var i in sc_libs) libs.push(i);
            var ancestor = util.fm_utils.find_common_aou_ancestor( libs );
            if (typeof ancestor == 'object' && ancestor != null) ancestor = ancestor.id();
            if (ancestor) {
                var ancestors = util.fm_utils.find_common_aou_ancestors( libs );
                var asc_list = get(ancestor, ancestors);
                for (var i = 0; i < asc_list.length; i++) {
                    g.add_stat_cat( asc_list[i] );
                }
            }
        }

		/* stat cats based on stat cat entries present on these copies */
        var sc_libs = {};
		for (var i = 0; i < g.copies.length; i++) {
			var entries = g.copies[i].stat_cat_entries();
			if (!entries) entries = [];
			for (var j = 0; j < entries.length; j++) {
                var lib = entries[j].owner(); if (typeof lib == 'object') lib = lib.id();
				sc_libs[ lib ] = true;
			}
        }
        add_common_ancestors(sc_libs); // CAVEAT - if a copy has no stat_cat_entries, it basically gets no vote here

        /* stat cats based on Circ Lib */
        sc_libs = {};
		for (var i = 0; i < g.copies.length; i++) {
            var circ_lib = g.copies[i].circ_lib(); if (typeof circ_lib == 'object') circ_lib = circ_lib.id();
            sc_libs[ circ_lib ] = true;
        }
        add_common_ancestors(sc_libs);

        /* stat cats based on Owning Lib */
        sc_libs = {};
		for (var i = 0; i < g.copies.length; i++) {
            var cn_id = g.copies[i].call_number();
			if (cn_id > 0) {
				if (! g.map_acn[ cn_id ]) {
                    var req = g.network.simple_request('FM_ACN_RETRIEVE.authoritative',[ cn_id ]);
                    if (typeof req.ilsevent == 'undefined') {
    					g.map_acn[ cn_id ] = req;
                    } else {
                        continue;
                    }
				}
                var owning_lib = g.map_acn[ cn_id ].owning_lib(); if (typeof owning_lib == 'object') owning_lib = owning_lib.id();
                sc_libs[ owning_lib ] = true;
			}
		}
        add_common_ancestors(sc_libs); // CAVEAT - if a copy is a pre-cat, it basically gets no vote here

        g.panes_and_field_names.right_pane4.sort();

    } catch(E) {
		alert(E);
        g.error.standard_unexpected_error_alert($('catStrings').getString('staff.cat.copy_editor.populate_stat_cat.error'),E);
    }
}


