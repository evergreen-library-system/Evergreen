if(!dojo._hasResource['openils.widget.AutoGrid']) {
    dojo.provide('openils.widget.AutoGrid');
    dojo.require('dojox.grid.DataGrid');
    dojo.require('openils.widget.AutoWidget');
    dojo.require('openils.widget.AutoFieldWidget');
    dojo.require('openils.widget.EditDialog');
    dojo.require('openils.Util');

    dojo.declare(
        'openils.widget.AutoGrid',
        [dojox.grid.DataGrid, openils.widget.AutoWidget],
        {

            /* if true, pop up an edit dialog when user hits Enter on a give row */
            editOnEnter : false, 

            startup : function() {
                this.inherited(arguments);
                this.initAutoEnv();
                var existing = (this.structure && this.structure[0].cells[0]) ? 
                    this.structure[0].cells[0] : [];
                var fields = [];
                for(var f in this.sortedFieldList) {
                    var field = this.sortedFieldList[f];
                    if(!field || field.virtual) continue;
                    var entry = existing.filter(function(i){return (i.field == field.name)})[0];
                    if(entry) entry.name = field.label;
                    else entry = {field:field.name, name:field.label};
                    fields.push(entry);
                    if(!entry.get) 
                        entry.get = openils.widget.AutoGrid.defaultGetter
                }
                this.setStructure([{cells: [fields]}]);
                this.setStore(this.buildAutoStore());
                if(this.editOnEnter) 
                    this._applyEditOnEnter();
            },

            /* capture keydown and launch edit dialog on enter */
            _applyEditOnEnter : function() {
                this.onMouseOverRow = function(e) {};
                this.onMouseOut = function(e) {};
                dojo.connect(this, 'onKeyDown',
                    function(e) {
                        if(e.keyCode == dojo.keys.ENTER) {
                            this.selection.deselectAll();
                            this.selection.select(this.focus.rowIndex);
                            this._drawEditDialog(this.selection.getFirstSelected());
                        }
                    }
                );
            },

            _drawEditDialog : function(storeItem) {
                var grid = this;
                var fmObject = new fieldmapper[this.fmClass]().fromStoreItem(storeItem);
                var idents = grid.store.getIdentityAttributes();
                var dialog = new openils.widget.EditDialog({
                    fmObject:fmObject,
                    onPostApply : function() {
                        for(var i in fmObject._fields) {
                            var field = fmObject._fields[i];
                            if(idents.filter(function(j){return (j == field)})[0])
                                continue; // don't try to edit an identifier field
                            grid.store.setValue(storeItem, field, fmObject[field]());
                        }
                        grid.update();
                        dialog.destroy();
                    }
                });
                dialog.editPane.fieldOrder = this.fieldOrder;
                dialog.startup();
                dialog.show();
            }
        }
    );
    openils.widget.AutoGrid.markupFactory = dojox.grid.DataGrid.markupFactory;

    openils.widget.AutoGrid.defaultGetter = function(rowIndex, item) {
        if(!item) return '';
        var val = this.grid.store.getValue(item, this.field);
        var autoWidget = new openils.widget.AutoFieldWidget({
            fmClass: this.grid.fmClass,
            fmField: this.field,
            widgetValue : val,
        });
        return autoWidget.getDisplayString();
    }
}

