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
dojo.require('dojo.cookie');
dojo.require('dojo.data.ItemFileWriteStore');
dojo.require('dojo.date.stamp');
dojo.require('dijit.form.NumberSpinner');
dojo.require('dijit.form.TextBox');
dojo.require('dijit.form.TimeTextBox');
dojo.require('dijit.form.ValidationTextBox');
dojo.require('dijit.form.CheckBox');
dojo.require('dijit.form.FilteringSelect');
dojo.require('dijit.Tree');
dojo.require('dijit.layout.ContentPane');
dojo.require('dijit.layout.TabContainer');
dojo.require('dijit.layout.LayoutContainer');
dojo.require('dijit.layout.SplitContainer');
dojo.require('dojox.widget.Toaster');
dojo.require('dojox.fx');
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

var current_type;
var current_fm_type;
var virgin_out_id = -1;

var highlighter = {};

var aout_strings = dojo.i18n.getLocalization('openils.conify', 'conify');

function status_update (markup) {
	if (parent !== window && parent.status_update) parent.status_update( markup );
}

function save_type () {

	var modified_aout = new aout().fromStoreItem( current_type );
	modified_aout.ischanged( 1 );

	new_kid_button.disabled = false;
	save_out_button.disabled = false;
	delete_out_button.disabled = false;

	pCRUD.update(modified_aout, {
		onerror : function (r) {
			highlighter.editor_pane.red.play();
			status_update( dojo.string.substitute(aout_strings.ERROR_SAVING_DATA, [ou_type_store.getValue( current_type, 'name' )] ) );
		},
		oncomplete : function (r) {
			ou_type_store.setValue( current_type, 'ischanged', 0 );
			highlighter.editor_pane.green.play();
			status_update( dojo.string.substitute(aout_strings.SUCCESS_SAVING_DATA, [ou_type_store.getValue( current_type, 'name' )] ) );
		}
	});
}

