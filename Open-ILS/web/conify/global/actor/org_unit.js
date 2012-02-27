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
var pcrud = new openils.PermaCrud({ authtoken : ses });

var current_ou, current_ou_hoo, ou_list_store;
var dirtyStore = [];
var virgin_ou_id = -1;

var aou_strings = dojo.i18n.getLocalization('openils.conify', 'conify');

//var ou_type_store = new dojo.data.ItemFileWriteStore({ data : aout.toStoreData( globalOrgTypes ) });

var highlighter = {};

function status_update (markup) {
    if (parent !== window && parent.status_update) parent.status_update( markup );
}

function save_org () {

    new_kid_button.disabled = false;
    save_ou_button.disabled = false;
    delete_ou_button.disabled = false;

    var modified_ou = new aou().fromStoreItem( current_ou );
    modified_ou.ischanged ( 1 );

    pcrud.apply( modified_ou, {
        timeout : 10, // makes it synchronous
        onerror : function (r) {
            highlighter.editor_pane.red.play();
            status_update( dojo.string.substitute( aou_strings.ERROR_SAVING_DATA, [ou_list_store.getValue( current_ou, 'name' )] ) );
        },
        oncomplete : function (r, list) {
            if ( list[0] ) {
                ou_list_store.setValue( current_ou, 'ischanged', 0 );
                highlighter.editor_pane.green.play();
                status_update( dojo.string.substitute( aou_strings.SUCCESS_SAVE, [ou_list_store.getValue( current_ou, 'name' )] ) );
            } else {
                highlighter.editor_pane.red.play();
                status_update( dojo.string.substitute( aou_strings.ERROR_SAVING_DATA, [ou_list_store.getValue( current_ou, 'name' )] ) );
            }
        },
    });

}
    
function hoo_load () {
    save_hoo_button.disabled = false;

    var hours_list = pcrud.search( 'aouhoo',{id:ou_list_store.getValue( current_ou, 'id' )});

    if (hours_list.length) {
        current_ou_hoo = hours_list[0];
        current_ou_hoo.ischanged(1); // XXX why?
    } else {
        current_ou_hoo = new aouhoo().fromHash({
            isnew   : 1,
            id      : ou_list_store.getValue( current_ou, 'id' )
        });
        for (var i = 0; i < 7; i++) {
            current_ou_hoo['dow_' + i + '_open']('09:00:00');
            current_ou_hoo['dow_' + i + '_close']('17:00:00');
        }
    }

    for (var i = 0; i < 7; i++) {
        window['dow_' + i + '_open'].setValue(
            dojo.date.stamp.fromISOString( 'T' + current_ou_hoo['dow_' + i + '_open']() )
        );
        window['dow_' + i + '_close'].setValue(
            dojo.date.stamp.fromISOString( 'T' + current_ou_hoo['dow_' + i + '_close']() )
        );
    }

    highlighter.hoo_pane.green.play();
}


function addr_load () {

    save_ill_address.disabled = false;
    save_holds_address.disabled = false;
    save_mailing_address.disabled = false;
    save_billing_address.disabled = false;

    atype_list = ['billing','mailing','holds','ill'];
    for (var addr_idx in atype_list) {

        var atype = atype_list[addr_idx];
        var cur_var_name =  'current_' + atype + '_address';

        var this_addr = pcrud.search( 'aoa',{id:ou_list_store.getValue( current_ou, atype + '_address')});

        if (this_addr.length) {
            window[cur_var_name] = this_addr[0];
            window[cur_var_name].ischanged( 1 ); // XXX why?
        } else {
            window[cur_var_name] = new aoa().fromHash({
                isnew       :   1,
                org_unit    :   ou_list_store.getValue( current_ou, 'id' )
            });
        }
        set_addr_inputs(atype);
    }

    highlighter.addresses_pane.green.play();

}

function set_addr_inputs (type) {
    window[type + '_addr_valid'].setChecked( window['current_' + type + '_address'].valid() == 't' ? true : false );
    window[type + '_addr_type'].setValue( window['current_' + type + '_address'].address_type() || '' );
    window[type + '_addr_street1'].setValue( window['current_' + type + '_address'].street1() || '' );
    window[type + '_addr_street2'].setValue( window['current_' + type + '_address'].street2() || '' );
    window[type + '_addr_city'].setValue( window['current_' + type + '_address'].city() || '' );
    window[type + '_addr_county'].setValue( window['current_' + type + '_address'].county() || '' );
    window[type + '_addr_country'].setValue( window['current_' + type + '_address'].country() || '' );
    window[type + '_addr_state'].setValue( window['current_' + type + '_address'].state() || '' );
    window[type + '_addr_post_code'].setValue( window['current_' + type + '_address'].post_code() || '' );
    window[type + '_addr_san'].setValue( window['current_' + type + '_address'].san() || '' );
}

