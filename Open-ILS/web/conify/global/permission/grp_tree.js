dojo.require('fieldmapper.dojoData');
dojo.require('dojo.parser');
dojo.require('dojo.data.ItemFileWriteStore');
dojo.require('dojo.date.stamp');
dojo.require('dijit.form.NumberSpinner');
dojo.require('dijit.form.TextBox');
dojo.require('dijit.form.TimeTextBox');
dojo.require('dijit.form.ValidationTextBox');
dojo.require('dijit.form.CheckBox');
dojo.require('dijit.form.FilteringSelect');
dojo.require('dijit.form.Textarea');
dojo.require('dijit.Tree');
dojo.require('dijit.layout.ContentPane');
dojo.require('dijit.layout.TabContainer');
dojo.require('dijit.layout.LayoutContainer');
dojo.require('dijit.layout.SplitContainer');
dojo.require('dojox.widget.Toaster');
dojo.require('dojox.fx');
//dojo.require('dojox.grid.Grid');

// some handy globals
var cgi = new CGI();
var cookieManager = new HTTP.Cookies();
var ses = cookieManager.read('ses') || cgi.param('ses');
var server = {};
server.pCRUD = new OpenSRF.ClientSession('open-ils.permacrud');
server.actor = new OpenSRF.ClientSession('open-ils.actor');

var current_group;
var virgin_out_id = -1;

var highlighter = {};

function status_update (markup) {
	if (parent !== window && parent.status_update) parent.status_update( markup );
}

function save_group () {

	var modified_pgt = new pgt().fromStoreItem( current_group );
	modified_pgt.ischanged( 1 );

	new_kid_button.disabled = false;
	save_out_button.disabled = false;
	delete_out_button.disabled = false;

	server.pCRUD.request({
		method : 'open-ils.permacrud.update.pgt',
		timeout : 10,
		params : [ ses, modified_pgt ],
		onerror : function (r) {
			highlighter.editor_pane.red.play();
			status_update( 'Problem saving data for ' + group_store.getValue( current_group, 'name' ) );
		},
		oncomplete : function (r) {
			var res = r.recv();
			if ( res && res.content() ) {
				group_store.setValue( current_group, 'ischanged', 0 );
				highlighter.editor_pane.green.play();
				status_update( 'Saved changes to ' + group_store.getValue( current_group, 'name' ) );
			} else {
				highlighter.editor_pane.red.play();
				status_update( 'Problem saving data for ' + group_store.getValue( current_group, 'name' ) );
			}
		},
	}).send();
}

