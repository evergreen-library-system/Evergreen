var docid; var marc_html; var top_pane; var bottom_pane; var opac_frame; var opac_url;

var marc_view_reset = true;
var marc_edit_reset = true;
var copy_browser_reset = true;
var hold_browser_reset = true;

function $(id) { return document.getElementById(id); }

function my_init() {
	try {
		netscape.security.PrivilegeManager.enablePrivilege("UniversalXPConnect");
		if (typeof JSAN == 'undefined') { throw(document.getElementById('offlineStrings').getString('common.jsan.missing')); }
		JSAN.errorLevel = "die"; // none, warn, or die
		JSAN.addRepository('..');
		JSAN.use('util.error'); g.error = new util.error();
		g.error.sdump('D_TRACE','my_init() for cat/opac.xul');

		JSAN.use('OpenILS.data'); g.data = new OpenILS.data(); g.data.init({'via':'stash'});
		XML_HTTP_SERVER = g.data.server_unadorned;

		JSAN.use('util.network'); g.network = new util.network();

		g.cgi = new CGI();
		try { authtime = g.cgi.param('authtime') || xulG.authtime; } catch(E) { g.error.sdump('D_ERROR',E); }
		try { docid = g.cgi.param('docid') || xulG.docid; } catch(E) { g.error.sdump('D_ERROR',E); }
		try { opac_url = g.cgi.param('opac_url') || xulG.opac_url; } catch(E) { g.error.sdump('D_ERROR',E); }

		JSAN.use('util.deck');
		top_pane = new util.deck('top_pane');
		bottom_pane = new util.deck('bottom_pane');

		set_opac();

	} catch(E) {
		var err_msg = document.getElementById("offlineStrings").getFormattedString("common.exception", ["cat/opac.xul", E]);
		try { g.error.sdump('D_ERROR',err_msg); } catch(E) { dump(err_msg); }
		alert(err_msg);
	}
}

function set_brief_view() {
	var url = xulG.url_prefix( urls.XUL_BIB_BRIEF ) + '?docid=' + window.escape(docid); 
	dump('spawning ' + url + '\n');
	top_pane.set_iframe( 
		url,
		{}, 
		{ 
			'set_tab_name' : function(n) { 
				if (typeof window.xulG == 'object' && typeof window.xulG.set_tab_name == 'function') {
					try { window.xulG.set_tab_name(document.getElementById('offlineStrings').getFormattedString("cat.bib_record", [n])); } catch(E) { alert(E); }
				} else {
					dump('no set_tab_name\n');
				}
			}
		}  
	);
}

function set_marc_view() {
	g.view = 'marc_view';
	if (marc_view_reset) {
		bottom_pane.reset_iframe( xulG.url_prefix( urls.XUL_MARC_VIEW ) + '?docid=' + window.escape(docid),{},xulG);
        marc_view_reset = false;
	} else {
		bottom_pane.set_iframe( xulG.url_prefix( urls.XUL_MARC_VIEW ) + '?docid=' + window.escape(docid),{},xulG);
	}
}

function set_marc_edit() {
	g.view = 'marc_edit';
	var a =	xulG.url_prefix( urls.XUL_MARC_EDIT );
	var b =	{};
	var c =	{
			'record' : { 'url' : '/opac/extras/supercat/retrieve/marcxml/record/' + docid },
			'save' : {
				'label' : document.getElementById('offlineStrings').getString('cat.save_record'),
				'func' : function (new_marcxml) {
					try {
						var r = g.network.simple_request('MARC_XML_RECORD_UPDATE', [ ses(), docid, new_marcxml ]);
                        marc_view_reset = true;
                        copy_browser_reset = true;
                        hold_browser_reset = true;
						if (typeof r.ilsevent != 'undefined') {
							throw(r);
						} else {
							alert(document.getElementById('offlineStrings').getString("cat.save.success"));
						}
					} catch(E) {
							g.error.standard_unexpected_error_alert(document.getElementById('offlineStrings').getString("cat.save.failure"), E);
					}
				}
			}
		};
	if (marc_edit_reset) {
		bottom_pane.reset_iframe( a,b,c );
        marc_edit_reset = false;
	} else {
		bottom_pane.set_iframe( a,b,c );
	}
}

function set_copy_browser() {
	g.view = 'copy_browser';
	if (copy_browser_reset) {
		bottom_pane.reset_iframe( xulG.url_prefix( urls.XUL_COPY_VOLUME_BROWSE ) + '?docid=' + window.escape(docid),{},xulG);
        copy_browser_reset =false;
	} else {
		bottom_pane.set_iframe( xulG.url_prefix( urls.XUL_COPY_VOLUME_BROWSE ) + '?docid=' + window.escape(docid),{},xulG);
	}
}

function set_hold_browser() {
	g.view = 'hold_browser';
	if (hold_browser_reset) {
		bottom_pane.reset_iframe( xulG.url_prefix( urls.XUL_HOLDS_BROWSER ) + '?docid=' + window.escape(docid),{},xulG);
        hold_browser_reset = false;
	} else {
		bottom_pane.set_iframe( xulG.url_prefix( urls.XUL_HOLDS_BROWSER ) + '?docid=' + window.escape(docid),{},xulG);
	}
}

function set_opac() {
	g.view = 'opac';
	try {
		var content_params = { 
			'show_nav_buttons' : true,
			'show_print_button' : true,
			'passthru_content_params' : { 
				'authtoken' : ses(), 
				'authtime' : ses('authtime'),
				'window_open' : function(a,b,c) {
					try {
						netscape.security.PrivilegeManager.enablePrivilege('UniversalXPConnect UniversalBrowserWrite');
						return window.open(a,b,c);
					} catch(E) {
						g.error.standard_unexpected_error_alert('window_open',E);
					}
				}
			},
			'on_url_load' : function(f) {
				netscape.security.PrivilegeManager.enablePrivilege("UniversalXPConnect");
				var win;
				try {
					if (typeof f.contentWindow.wrappedJSObject.attachEvt != 'undefined') {
						win = f.contentWindow.wrappedJSObject;
					} else {
						win = f.contentWindow;
					}
				} catch(E) {
					win = f.contentWindow;
				}
				win.attachEvt("rdetail", "recordRetrieved",
					function(id){
						try {
							if (docid == id) return;
							docid = id;
							refresh_display(id);
						} catch(E) {
							g.error.standard_unexpected_error_alert('rdetail -> recordRetrieved',E);
						}
					}
				);
				
				g.f_record_start = null; g.f_record_prev = null; g.f_record_next = null; g.f_record_end = null;
				$('record_start').disabled = true; $('record_next').disabled = true;
				$('record_prev').disabled = true; $('record_end').disabled = true;
				$('record_pos').setAttribute('value','');

				win.attachEvt("rdetail", "nextPrevDrawn",
					function(rIndex,rCount){
						$('record_pos').setAttribute('value', document.getElementById('offlineStrings').getFormattedString('cat.record.counter', [(1+rIndex), rCount]));
						if (win.rdetailNext) {
							g.f_record_next = function() { 
								g.view_override = g.view; 
								win.rdetailNext(); 
							}
							$('record_next').disabled = false;
						}
						if (win.rdetailPrev) {
							g.f_record_prev = function() { 
								g.view_override = g.view; 
								win.rdetailPrev(); 
							}
							$('record_prev').disabled = false;
						}
						if (win.rdetailStart) {
							g.f_record_start = function() { 
								g.view_override = g.view; 
								win.rdetailStart(); 
							}
							$('record_start').disabled = false;
						}
						if (win.rdetailEnd) {
							g.f_record_end = function() { 
								g.view_override = g.view; 
								win.rdetailEnd(); 
							}
							$('record_end').disabled = false;
						}
					}
				);
			},
			'url_prefix' : xulG.url_prefix,
		};
		if (opac_url) { content_params.url = opac_url; } else { content_params.url = xulG.url_prefix( urls.browser ); }
		browser_frame = bottom_pane.set_iframe( xulG.url_prefix(urls.XUL_REMOTE_BROWSER) + '?name=Catalog', {}, content_params);
	} catch(E) {
		g.error.sdump('D_ERROR','set_opac: ' + E);
	}
}

function bib_in_new_tab() {
	try {
		var url = browser_frame.contentWindow.g.browser.controller.view.browser_browser.contentWindow.wrappedJSObject.location.href;
		var content_params = { 'session' : ses(), 'authtime' : ses('authtime'), 'opac_url' : url };
		xulG.new_tab(xulG.url_prefix(urls.XUL_OPAC_WRAPPER), {}, content_params);
	} catch(E) {
		g.error.sdump('D_ERROR',E);
	}
}

function remove_me() {
	var url = xulG.url_prefix( urls.XUL_BIB_BRIEF ) + '?docid=' + window.escape(docid);
	dump('removing ' + url + '\n');
	try { top_pane.remove_iframe( url ); } catch(E) { dump(E + '\n'); }
	$('nav').setAttribute('hidden','true');
}

function add_to_bucket() {
	JSAN.use('util.window'); var win = new util.window();
	win.open(
		xulG.url_prefix(urls.XUL_RECORD_BUCKETS_QUICK)
		+ '?record_ids=' + js2JSON( [ docid ] ),
		'sel_bucket_win' + win.window_name_increment(),
		'chrome,resizable,modal,center'
	);
}

function mark_for_overlay() {
	g.data.marked_record = docid;
	g.data.stash('marked_record');
	var robj = g.network.simple_request('MODS_SLIM_RECORD_RETRIEVE.authoritative',[docid]);
    if (typeof robj.ilsevent == 'undefined') {
        g.data.marked_record_mvr = robj;
    } else {
        g.data.marked_record_mvr = null;
		g.error.standard_unexpected_error_alert('in mark_for_overlay',robj);
    }
    g.data.stash('marked_record_mvr');
    if (g.data.marked_record_mvr) {
        alert(document.getElementById('offlineStrings').getFormattedString('cat.opac.record_marked_for_overlay.tcn.alert',[ g.data.marked_record_mvr.tcn() ]));
    } else {
        alert(document.getElementById('offlineStrings').getFormattedString('cat.opac.record_marked_for_overlay.record_id.alert',[ g.data.marked_record  ]));
    }
}

function delete_record() {
	if (g.error.yns_alert(
		document.getElementById('offlineStrings').getFormattedString('cat.opac.delete_record.confirm', [docid]),
		document.getElementById('offlineStrings').getString('cat.opac.delete_record'),
		document.getElementById('offlineStrings').getString('cat.opac.delete'),
		document.getElementById('offlineStrings').getString('cat.opac.cancel'),
		null,
		document.getElementById('offlineStrings').getString('cat.opac.record_deleted.confirm')) == 0) {
		var robj = g.network.simple_request('FM_BRE_DELETE',[ses(),docid]);
		if (typeof robj.ilsevent != 'undefined') {
			alert(document.getElementById('offlineStrings').getFormattedString('cat.opac.record_deleted.error',  [docid, robj.textcode, robj.desc]) + '\n');
		} else {
			alert(document.getElementById('offlineStrings').getString('cat.opac.record_deleted'));
			refresh_display(docid);
		}
	}
}

function undelete_record() {
    if (g.error.yns_alert(
		document.getElementById('offlineStrings').getFormattedString('cat.opac.undelete_record.confirm', [docid]),
		document.getElementById('offlineStrings').getString('cat.opac.undelete_record'),
		document.getElementById('offlineStrings').getString('cat.opac.undelete'),
		document.getElementById('offlineStrings').getString('cat.opac.cancel'),
		null,
		document.getElementById('offlineStrings').getString('cat.opac.record_undeleted.confirm')) == 0) {

        var robj = g.network.simple_request('FM_BRE_UNDELETE',[ses(),docid]);
        if (typeof robj.ilsevent != 'undefined') {
			alert(document.getElementById('offlineStrings').getFormattedString('cat.opac.record_undeleted.error',  [docid, robj.textcode, robj.desc]) + '\n');
        } else {
			alert(document.getElementById('offlineStrings').getString('cat.opac.record_undeleted'));
			refresh_display(docid);
        }
    }
}

function refresh_display(id) {
	try { 
        marc_view_reset = true;
        marc_edit_reset = true;
        copy_browser_reset = true;
        hold_browser_reset = true;
		while(top_pane.node.lastChild) top_pane.node.removeChild( top_pane.node.lastChild );
		var children = bottom_pane.node.childNodes;
		for (var i = 0; i < children.length; i++) {
			if (children[i] != browser_frame) bottom_pane.node.removeChild(children[i]);
		}

		set_brief_view();
		$('nav').setAttribute('hidden','false');
		var settings = g.network.simple_request(
			'FM_AUS_RETRIEVE',
			[ ses(), g.data.list.au[0].id() ]
		);
		var view = settings['staff_client.catalog.record_view.default'];
		if (g.view_override) {
			view = g.view_override;
			g.view_override = null;
		}
		switch(view) {
			case 'marc_view' : set_marc_view(); break;
			case 'marc_edit' : set_marc_edit(); break;
			case 'copy_browser' : set_copy_browser(); break;
			case 'hold_browser' : set_hold_browser(); break;
			case 'opac' :
			default: set_opac(); break;
		}
	} catch(E) {
		g.error.standard_unexpected_error_alert('in refresh_display',E);
	}
}

function set_default() {
	var robj = g.network.simple_request(
		'FM_AUS_UPDATE',
		[ ses(), g.data.list.au[0].id(), { 'staff_client.catalog.record_view.default' : g.view } ]
	)
	if (typeof robj.ilsevent != 'undefined') {
		if (robj.ilsevent != 0) g.error.standard_unexpected_error_alert(document.getElementById('offlineStrings').getString('cat.preference.error'), robj);
	}
}


