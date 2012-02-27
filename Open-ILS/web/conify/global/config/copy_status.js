/*
# ---------------------------------------------------------------------------
# Copyright (C) 2008  Georgia Public Library Service / Equinox Software, Inc
# Mike Rylander <miker@esilibrary.com>
# 
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
# 
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
# ---------------------------------------------------------------------------
*/

dojo.require('fieldmapper.AutoIDL');
dojo.require('fieldmapper.dojoData');
dojo.require('openils.widget.TranslatorPopup');
dojo.require('openils.PermaCrud');
dojo.require('dojo.parser');
dojo.require('dojo.string');
dojo.require('dojo.data.ItemFileWriteStore');
dojo.require('dojo.cookie');
dojo.require('dijit.form.TextBox');
dojo.require('dijit.form.ValidationTextBox');
dojo.require('dijit.form.Textarea');
dojo.require('dijit.layout.ContentPane');
dojo.require('dijit.layout.LayoutContainer');
dojo.require('dijit.layout.BorderContainer');
dojo.require('dojox.widget.Toaster');
dojo.require('dojox.fx');
dojo.require('dojox.grid.Grid');
dojo.require('openils.XUL');
dojo.requireLocalization("openils.conify", "conify");

// some handy globals
var cgi = new CGI();
var ses = dojo.cookie('ses') || cgi.param('ses');
if(!ses && openils.XUL.isXUL()) {
    var stash = openils.XUL.getStash();
    ses = stash.session.key;
}
var pCRUD = new openils.PermaCrud({authtoken:ses});

var current_status;
var virgin_out_id = -1;

var ccs_strings = dojo.i18n.getLocalization('openils.conify', 'conify');

var highlighter = {};

function status_update (markup) {
	if (parent !== window && parent.status_update) parent.status_update( markup );
}

function save_status () {

	var modified_ccs = new ccs().fromStoreItem( current_status );
	modified_ccs.ischanged( 1 );

	pCRUD.update(modified_ccs, {
		onerror : function (r) {
			highlighter.red.play();
			status_update( dojo.string.substitute(ccs_strings.ERROR_SAVING_STATUS, [status_store.getValue( current_status, 'name' )]) );
		},
		oncomplete : function (r) {
			status_store.setValue( current_status, 'ischanged', 0 );
			highlighter.green.play();
			status_update( dojo.string.substitute(ccs_strings.SUCCESS_SAVE, [status_store.getValue( current_status, 'name' )]) );
		}
	});
}

function save_them_all (event) {

	status_store.fetch({
		query : { ischanged : 1 },
		onItem : function (item, req) { try { if (this.isItem( item )) window.dirtyStore.push( item ); } catch (e) { /* meh */ } },
		scope : status_store
	});

	var confirmation = true;


	if (event && dirtyStore.length > 0) {
		confirmation = confirm(
			ccs_strings.CONFIRM_EXIT_CCS
		);
	}

	if (confirmation) {
		for (var i in window.dirtyStore) {
			window.current_status = window.dirtyStore[i];
			save_status(true);
		}

		window.dirtyStore = [];
	}
}

dojo.addOnUnload( save_them_all );

