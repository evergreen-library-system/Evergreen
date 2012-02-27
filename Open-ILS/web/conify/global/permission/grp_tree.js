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
dojo.require('openils.PermaCrud');
dojo.require('openils.widget.TranslatorPopup');
dojo.require('dojo.parser');
dojo.require('dojo.data.ItemFileWriteStore');
dojo.require('dojo.date.stamp');
dojo.require('dojo.cookie');
dojo.require('dijit.form.NumberSpinner');
dojo.require('dijit.form.TextBox');
dojo.require('dijit.form.TimeTextBox');
dojo.require('dijit.form.ValidationTextBox');
dojo.require('dijit.form.CheckBox');
dojo.require('dijit.form.FilteringSelect');
dojo.require('dijit.form.Textarea');
dojo.require('dijit.form.Button');
dojo.require('dijit.Dialog');
dojo.require('dijit.Tree');
dojo.require('dijit.layout.ContentPane');
dojo.require('dijit.layout.TabContainer');
dojo.require('dijit.layout.LayoutContainer');
dojo.require('dijit.layout.SplitContainer');
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
var server = {};
server.pcrud = new openils.PermaCrud({ authtoken : ses });
server.actor = new OpenSRF.ClientSession('open-ils.actor');

var pgt_strings = dojo.i18n.getLocalization('openils.conify', 'conify');

var virgin_out_id = -1;

var highlighter = {};

function status_update (markup) {
	if (parent !== window && parent.status_update) parent.status_update( markup );
}

function save_group () {

	var modified_pgt = new pgt().fromStoreItem( current_group );
	modified_pgt.ischanged( 1 );

	new_kid_button.disabled = false;
	save_group_button.disabled = false;
	delete_group_button.disabled = false;

	server.pcrud.update(modified_pgt, {
		onerror : function (r) {
			highlighter.editor_pane.red.play();
			status_update( dojo.string.substitute( pgt_strings.ERROR_SAVING_DATA, [group_store.getValue( current_group, 'name' )]) );
		},
		oncomplete : function (r) {
			group_store.setValue( current_group, 'ischanged', 0 );
			highlighter.editor_pane.green.play();
			status_update( dojo.string.substitute(pgt_strings.SUCCESS_SAVE, [group_store.getValue( current_group, 'name' )]) );
		},
	});
}

function save_perm_map (storeItem) {

	var modified_pgpm = new pgpm().fromStoreItem( storeItem );
	modified_pgpm.ischanged( 1 );

	server.pcrud.update(modified_pgpm, {
		onerror : function (r) {
			highlighter.editor_pane.red.play();
			status_update( dojo.string.substitute(pgt_strings.ERROR_SAVING_PERM_DATA, [group_store.getValue( current_group, 'name' )]) );
		},
		oncomplete : function (r) {
			perm_map_store.setValue( storeItem, 'ischanged', 0 );
			highlighter.editor_pane.green.play();
			status_update( dojo.string.substitute(pgt_strings.SUCCESS_SAVE_PERM, [group_store.getValue( current_group, 'name' )]) );
		},
	});
}

function save_them_all (event) {

	var dirtyMaps = [];

    perm_map_store.fetch({
        query : { ischanged : 1 },
        onItem : function (item, req) { try { if (this.isItem( item )) dirtyMaps.push( item ); } catch (e) { /* meh */ } },
        scope : perm_map_store
    });

    var confirmation = true;


    if (event && dirtyMaps.length > 0) {
        confirmation = confirm( pgt_strings.CONFIRM_EXIT);
    }

    if (confirmation) {
        for (var i in dirtyMaps) {
            save_perm_map(dirtyMaps[i]);
        }
    }
}

dojo.addOnUnload( save_them_all );

