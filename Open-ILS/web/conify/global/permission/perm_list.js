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

dojo.require('fieldmapper.dojoData');
dojo.require('openils.widget.TranslatorPopup');
dojo.require('dojo.parser');
dojo.require('dojo.string');
dojo.require('dojo.data.ItemFileWriteStore');
dojo.require('dijit.form.TextBox');
dojo.require('dijit.form.ValidationTextBox');
dojo.require('dijit.form.Textarea');
dojo.require('dijit.layout.ContentPane');
dojo.require('dijit.layout.LayoutContainer');
dojo.require('dijit.layout.BorderContainer');
dojo.require('dojox.widget.Toaster');
dojo.require('dojox.fx');
dojo.require('dojox.grid.Grid');
dojo.require('dojox.grid.compat._data.model');
dojo.require("dojox.grid.compat._data.editors");

// some handy globals
var cgi = new CGI();
var cookieManager = new HTTP.Cookies();
var ses = cookieManager.read('ses') || cgi.param('ses');
var pCRUD = new OpenSRF.ClientSession('open-ils.permacrud');

var current_perm;
var virgin_out_id = -1;

var highlighter = {};

function status_update (markup) {
	if (parent !== window && parent.status_update) parent.status_update( markup );
}

function save_perm () {

	var modified_ppl = new ppl().fromStoreItem( current_perm );
	modified_ppl.ischanged( 1 );
	modified_ppl.description( dojo.string.trim( modified_ppl.description() ) );
	modified_ppl.code( dojo.string.trim( modified_ppl.code() ) );

	pCRUD.request({
		method : 'open-ils.permacrud.update.ppl',
		timeout : 10,
		params : [ ses, modified_ppl ],
		onerror : function (r) {
			highlighter.red.play();
			status_update( 'Problem saving data for ' + perm_store.getValue( current_perm, 'code' ) );
		},
		oncomplete : function (r) {
			var res = r.recv();
			if ( res && res.content() ) {
				perm_store.setValue( current_perm, 'ischanged', 0 );
				highlighter.green.play();
				status_update( 'Saved changes to ' + perm_store.getValue( current_perm, 'code' ) );
			} else {
				highlighter.red.play();
				status_update( 'Problem saving data for ' + perm_store.getValue( current_perm, 'code' ) );
			}
		},
	}).send();
}

function save_them_all (event) {

	perm_store.fetch({
		query : { ischanged : 1 },
		onItem : function (item, req) { try { if (this.isItem( item )) window.dirtyStore.push( item ); } catch (e) { /* meh */ } },
		scope : perm_store
	});

	var confirmation = true;


	if (event && dirtyStore.length > 0) {
		confirmation = confirm(
			'There are unsaved modified Permissions!  '+
			'OK to save these changes, Cancel to abandon them.'
		);
	}

	if (confirmation) {
		for (var i in window.dirtyStore) {
			window.current_perm = window.dirtyStore[i];
			save_perm(true);
		}

		window.dirtyStore = [];
	}
}

dojo.addOnUnload( save_them_all );

