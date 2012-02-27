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
dojo.require('dojo.cookie');
dojo.require('dojo.parser');
dojo.require('dojo.string');
dojo.require('dojo.data.ItemFileWriteStore');
dojo.require('dijit.form.Form');
dojo.require('dijit.form.TextBox');
dojo.require('dijit.form.ValidationTextBox');
dojo.require('dijit.form.Textarea');
dojo.require('dijit.layout.TabContainer');
dojo.require('dijit.layout.ContentPane');
dojo.require('dijit.layout.LayoutContainer');
dojo.require('dijit.layout.BorderContainer');
dojo.require('dojox.widget.Toaster');
dojo.require('dojox.fx');
dojo.require('dojox.grid.Grid');
dojo.require('openils.XUL');
dojo.requireLocalization("openils.conify", "conify");

console.log('loading marc_code_maps.js');

// some handy globals
var cgi = new CGI();
var ses = dojo.cookie('ses') || cgi.param('ses');
if(!ses && openils.XUL.isXUL()) {
    var stash = openils.XUL.getStash();
    ses = stash.session.key;
}
var pCRUD = new openils.PermaCrud({authtoken:ses});

console.log('initialized pcrud session');

var stores = {};
var current_item = {};

var cam_strings = dojo.i18n.getLocalization('openils.conify', 'conify');

/*
var highlighter = {
	green : dojox.fx.highlight( { color : '#B4FFB4', node : 'grid_container', duration : 500 } ),
	red : dojox.fx.highlight( { color : '#FF2018', node : 'grid_container', duration : 500 } )
};

console.log('highlighters set up');
*/

var dirtyStore = [];

function status_update (markup) {
	if (parent !== window && parent.status_update) parent.status_update( markup );
}

console.log('local status function built');

function save_code (classname) {

	var item = current_item[classname];
	var obj = new fieldmapper[classname]().fromStoreItem( item );

	obj.ischanged( 1 );
	obj.code( dojo.string.trim( obj.code() ) );
	obj.value( dojo.string.trim( obj.value() ) );
	if(classname == 'cam' || classname == 'clfm')
		obj.description( dojo.string.trim( obj.description() ) );

	pCRUD.update(obj, {
		onerror : function (r) {
			//highlighter.red.play();
			status_update( dojo.string.substitute(cam_strings.ERROR_SAVING_DATA_CAM, [classname, obj.code()]) );
		},
		oncomplete : function (r) {
			stores[classname].setValue( current_item, 'ischanged', 0 );
			status_update( dojo.string.substitute(cam_strings.SUCCESS_SAVE, stores[classname].getValue( item, 'code' )) );
		}
	});
}

function save_them_all (event) {

	for (var classname in stores) {

		var store = stores[classname];
		store.fetch({
			query : { ischanged : 1 },
			onItem : function (item, req) { try { if (this.isItem( item )) window.dirtyStore.push( item ); } catch (e) { /* meh */ } },
			scope : store
		});

		var confirmation = true;

		if (event && dirtyStore.length > 0) {
			confirmation = confirm( cam_strings.CONFIRM_EXIT_CAM );
			event = null;
		}

		if (confirmation) {
			for (var i in dirtyStore) {
				current_item[classname] = dirtyStore[i];
				save_object(classname);
			}

			dirtyStore = [];
		}
	}
}

dojo.addOnUnload( save_them_all );

function delete_grid_selection(classname, grid ) {

    var selected_rows = grid.selection.getSelected();
        
    var selected_items = [];
    for (var i in selected_rows) {
        selected_items.push(
            grid.model.getRow( selected_rows[i] ).__dojo_data_item
        );
    }

    grid.selection.clear();

    for (var i in selected_items) {
        var item = selected_items[i];

        if ( confirm( dojo.string.substitute( cam_strings.CONFIRM_DELETE, [grid.model.store.getValue( item, 'value' )] ) ) ) {

            grid.model.store.setValue( item, 'isdeleted', 1 );
            
            var obj = new fieldmapper[classname]().fromStoreItem( item );
            obj.isdeleted( 1 );
            
            pCRUD.eliminate(obj, {
                onerror : function (r) {
                    //highlighter.red.play();
                    status_update( dojo.string.substitute( cam_strings.ERROR_DELETING, [grid.model.store.getValue( item, 'value' )] ) );
                },
                oncomplete : function (r) {
                    grid.model.store.fetch({
                        query : { code : grid.model.store.getValue( item, 'code' ) },
                        onItem : function (item, req) { try { if (this.isItem( item )) this.deleteItem( item ); } catch (e) { /* meh */ } },
                        scope : grid.model.store
                    });
            
                    status_update( dojo.string.substitute( cam_strings.STATUS_DELETED, [old_name] ) );
                }
            });
        
        }
    }
}

function create_marc_code (data) {

	var cl = data.classname;
	if (!cl) return false;

	data.code = dojo.string.trim( data.code );
	data.value = dojo.string.trim( data.value );

	if(!data.code || !data.value) return false;

	if(cl == 'cam' || cl == 'clfm')
		data.description = dojo.string.trim( data.description );

    var new_fm_obj = new fieldmapper[cl]().fromHash( data )
    new_fm_obj.isnew(1);

    var err = false;
    pCRUD.create(new_fm_obj, {
        onerror : function (r) {
            //highlighter.red.play();
            status_update( dojo.string.substitute( cam_strings.ERROR_CALLING_METHOD_CAM, [cl] ) );
            err = true;
        },
        oncomplete : function (r, list) {
            var new_item_hash = list[0].toHash();
            stores[cl].newItem( new_item_hash );
            status_update( dojo.string.substitute( cam_strings.SUCCESS_CREATING_CODE, [new_item_hash.code, cl] ) );
            //highlighter.green.play();
        }
    });

	return false;
}

