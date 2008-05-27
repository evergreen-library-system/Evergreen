if(!dojo._hasResource["openils.editors"]){
dojo._hasResource["openils.editors"] = true;
dojo.provide("openils.editors");

dojo.require("dojox.grid._data.dijitEditors");
dojo.require("dojox.grid._data.editors");
dojo.require("dijit.form.NumberSpinner");
dojo.require('dijit.form.FilteringSelect');

dojo.declare("openils.editors.NumberSpinner", dojox.grid.editors.Dijit, {
    editorClass: "dijit.form.NumberSpinner",

    getvalue: function() {
	var e = this.editor;
	// make sure to apply the displayed value
	e.setDisplayedValue(e.getDisplayedValue());
	return e.getValue();
    },

    getEditorProps: function(inDatum){
	return dojo.mixin({}, this.cell.editorProps||{}, {
	    constraints: dojo.mixin({}, this.cell.constraints) || {},
	    value: inDatum
	});
    },
});

dojo.declare('openils.editors.FundSelectEditor', dojox.grid.editors.Dijit, {
    editorClass: "openils.widget.FundSelector",
    createEditor: function(inNode, inDatum, inRowIndex) {
	var editor = new this.editorClass(this.getEditorProps(inDatum), inNode);
	globalUser.buildPermFundSelector(this.cell.perm || this.perm,
					 editor);
	return editor;
    },
});

}
