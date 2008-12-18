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
dojo.requireLocalization("openils.conify", "conify");

// some handy globals
var cgi = new CGI();
var cookieManager = new HTTP.Cookies();
var ses = cookieManager.read('ses') || cgi.param('ses');
var pCRUD = new OpenSRF.ClientSession('open-ils.pcrud');

var current_ou, current_ou_hoo;
var virgin_ou_id = -1;

var aou_strings = dojo.i18n.getLocalization('openils.conify', 'conify');

//var ou_type_store = new dojo.data.ItemFileWriteStore({ data : aout.toStoreData( globalOrgTypes ) });

var highlighter = {};

function status_update (markup) {
	if (parent !== window && parent.status_update) parent.status_update( markup );
}

function save_org () {
	var modified_ou = new aou().fromStoreItem( current_ou );
	modified_ou.ischanged( 1 );

	new_kid_button.disabled = false;
	save_ou_button.disabled = false;
	delete_ou_button.disabled = false;

    if (!pCRUD.connect()) {
		highlighter.editor_pane.red.play();
		status_update( dojo.string.substitute( aou_strings.ERROR_SAVING_DATA, [ou_list_store.getValue( current_ou, 'name' )] ) );
        return null;
    }
    
	var commit = pCRUD.request({
		method : 'open-ils.pcrud.transaction.commit',
		timeout : 10,
		params : [ ses, modified_ou ],
		onerror : function (r) {
			highlighter.editor_pane.red.play();
			status_update( dojo.string.substitute( aou_strings.ERROR_SAVING_DATA, [ou_list_store.getValue( current_ou, 'name' )] ) );
            pCRUD.disconnect();
            throw 'commit error';
		},
		oncomplete : function (r) {
			var res = r.recv();
			if ( res ) {
				ou_list_store.setValue( current_ou, 'ischanged', 0 );
				highlighter.editor_pane.green.play();
				status_update( dojo.string.substitute( aou_strings.SUCCESS_SAVE, [ou_list_store.getValue( current_ou, 'name' )] ) );
			} else {
				highlighter.editor_pane.red.play();
				status_update( dojo.string.substitute( aou_strings.ERROR_SAVING_DATA, [ou_list_store.getValue( current_ou, 'name' )] ) );
                throw 'commit error';
			}
            pCRUD.disconnect();
		},
	});

	var update = pCRUD.request({
		method : 'open-ils.pcrud.update.aou',
		timeout : 10,
		params : [ ses, modified_ou ],
		onerror : function (r) {
			highlighter.editor_pane.red.play();
			status_update( dojo.string.substitute( aou_strings.ERROR_SAVING_DATA, [ou_list_store.getValue( current_ou, 'name' )] ) );
            pCRUD.disconnect();
            throw 'update error';
		},
		oncomplete : function (r) {
			var res = r.recv();
			if ( res && res.content() ) {
                commit.send();
			} else {
				highlighter.editor_pane.red.play();
				status_update( dojo.string.substitute( aou_strings.ERROR_SAVING_DATA, [ou_list_store.getValue( current_ou, 'name' )] ) );
                pCRUD.disconnect();
                throw 'update error';
			}
		},
	});

	var begin = pCRUD.request({
		method : 'open-ils.pcrud.transaction.begin',
		timeout : 10,
		params : [ ses, modified_ou ],
		onerror : function (r) {
			highlighter.editor_pane.red.play();
			status_update( dojo.string.substitute( aou_strings.ERROR_SAVING_DATA, [ou_list_store.getValue( current_ou, 'name' )] ) );
            pCRUD.disconnect();
            throw 'begin error';
		},
		oncomplete : function (r) {
			var res = r.recv();
			if ( res && res.content() ) {
                update.send();
			} else {
				highlighter.editor_pane.red.play();
				status_update( dojo.string.substitute( aou_strings.ERROR_SAVING_DATA, [ou_list_store.getValue( current_ou, 'name' )] ) );
                pCRUD.disconnect();
                throw 'begin error';
			}
		},
	});

    begin.send();
}
	
function hoo_load () {
	// empty result not coming through ...
	current_ou_hoo = new aouhoo().fromHash({id:ou_list_store.getValue( current_ou, 'id' )});
	current_ou_hoo.isnew(1);

	pCRUD.request({
		method : 'open-ils.pcrud.retrieve.aouhoo',
		params : [ ses, ou_list_store.getValue( current_ou, 'id' ) ],
		onerror : function (r) { 
			throw dojo.string.substitute(aou_strings.ERROR_FETCHING_HOURS, [ou_list_store.getValue( current_ou, 'name' )]);
		},
		oncomplete : function (r) {
			current_ou_hoo = null;

			var res = r.recv();
			if (res) {
				if (res.content()) current_ou_hoo = res.content();
			}

			if (!current_ou_hoo) {
				current_ou_hoo = new aouhoo().fromHash({id:ou_list_store.getValue( current_ou, 'id' )});
				current_ou_hoo.isnew(1);
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
	}).send();

}

function addr_load () {
	// empty result not coming through ...

	save_ill_address.disabled = false;
	save_holds_address.disabled = false;
	save_mailing_address.disabled = false;
	save_billing_address.disabled = false;

	if (ou_list_store.getValue( current_ou, 'billing_address' )) {
		pCRUD.request({
			method : 'open-ils.pcrud.retrieve.aoa',
			params : [ ses, ou_list_store.getValue( current_ou, 'billing_address' ) ],
			onerror : function (r) {
				throw dojo.string.substitute(aou_strings.ERROR_FETCHING_PHYSICAL, [ou_list_store.getValue( current_ou, 'name' )]);
			},
			oncomplete : function (r) {
				current_billing_address = null;

				var res = r.recv();
				if (res) {
					if (res.content()) current_billing_address = res.content();
				}

				if (!current_billing_address) {
					current_billing_address = new aoa().fromHash({org_unit:ou_list_store.getValue( current_ou, 'id' )});
					current_billing_address.isnew(1);
				}

				set_addr_inputs('billing');
				highlighter.addresses_pane.green.play();
			}
		}).send();
	} else {
		current_billing_address = new aoa().fromHash({org_unit:ou_list_store.getValue( current_ou, 'id' )});
		current_billing_address.isnew(1);
		set_addr_inputs('billing');
	}

	if (ou_list_store.getValue( current_ou, 'mailing_address' )) {
		pCRUD.request({
			method : 'open-ils.pcrud.retrieve.aoa',
			params : [ ses, ou_list_store.getValue( current_ou, 'mailing_address' ) ],
			onerror : function (r) {
				throw dojo.string.substitute(aou_strings.ERROR_FETCHING_MAILING, [ou_list_store.getValue( current_ou, 'name' )]);
			},
			oncomplete : function (r) {
				current_mailing_address = null;

				var res = r.recv();
				if (res) {
					if (res.content()) current_mailing_address = res.content();
				}

				if (!current_mailing_address) {
					current_mailing_address = new aoa().fromHash({org_unit:ou_list_store.getValue( current_ou, 'id' )});
					current_mailing_address.isnew(1);
				}

				set_addr_inputs('mailing');
				highlighter.addresses_pane.green.play();
			}
		}).send();
	} else {
		current_mailing_address = new aoa().fromHash({org_unit:ou_list_store.getValue( current_ou, 'id' )});
		current_mailing_address.isnew(1);
		set_addr_inputs('mailing');
	}

	if (ou_list_store.getValue( current_ou, 'holds_address' )) {
		pCRUD.request({
			method : 'open-ils.pcrud.retrieve.aoa',
			params : [ ses, ou_list_store.getValue( current_ou, 'holds_address' ) ],
			onerror : function (r) {
				throw dojo.string.substitute(aou_strings.ERROR_FETCHING_HOLDS, [ou_list_store.getValue( current_ou, 'name' )]);
			},
			oncomplete : function (r) {
				current_holds_address = null;

				var res = r.recv();
				if (res) {
					if (res.content()) current_holds_address = res.content();
				}

				if (!current_holds_address) {
					current_holds_address = new aoa().fromHash({org_unit:ou_list_store.getValue( current_ou, 'id' )});
					current_holds_address.isnew(1);
				}

				set_addr_inputs('holds');
				highlighter.addresses_pane.green.play();
			}
		}).send();
	} else {
		current_holds_address = new aoa().fromHash({org_unit:ou_list_store.getValue( current_ou, 'id' )});
		current_holds_address.isnew(1);
		set_addr_inputs('holds');
	}

	if (ou_list_store.getValue( current_ou, 'ill_address' )) {
		pCRUD.request({
			method : 'open-ils.pcrud.retrieve.aoa',
			params : [ ses, ou_list_store.getValue( current_ou, 'ill_address' ) ],
			onerror : function (r) {
				throw dojo.string.substitute(aou_strings.ERROR_FETCHING_ILL, [ou_list_store.getValue( current_ou, 'name' )]);
			},
			oncomplete : function (r) {
				current_ill_address = null;

				var res = r.recv();
				if (res) {
					if (res.content()) current_ill_address = res.content();
				}

				if (!current_ill_address) {
					current_ill_address = new aoa().fromHash({org_unit:ou_list_store.getValue( current_ou, 'id' )});
					current_ill_address.isnew(1);
				}

				set_addr_inputs('ill');
				highlighter.addresses_pane.green.play();
			}
		}).send();
	} else {
		current_ill_address = new aoa().fromHash({org_unit:ou_list_store.getValue( current_ou, 'id' )});
		current_ill_address.isnew(1);
		set_addr_inputs('ill');
	}

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
}

