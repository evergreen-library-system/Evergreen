dojo.require('conify.fieldmapper.addToHash', true);
dojo.require('conify.fieldmapper.addFromHash', true);
dojo.require('conify.fieldmapper.addToStoreData', true);
dojo.require('conify.fieldmapper.addFromStoreItem', true);
dojo.require('dojo.parser');
dojo.require('dojo.data.ItemFileWriteStore');
dojo.require('dijit.form.TextBox');
dojo.require('dijit.form.ValidationTextBox');
dojo.require('dijit.form.Textarea');
dojo.require('dijit.layout.ContentPane');
dojo.require('dojox.widget.Toaster');
dojo.require('dojox.fx');
dojo.require('dojox.grid.Grid');
dojo.require('dojox.grid._data.model');
dojo.require("dojox.grid.editors");

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

	new_kid_button.disabled = false;
	save_out_button.disabled = false;
	delete_out_button.disabled = false;

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

