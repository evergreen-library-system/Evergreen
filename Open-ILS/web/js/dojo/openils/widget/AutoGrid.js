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
            defaultCellWidth : null,

            startup : function() {

                this.selectionMode = 'single';
                this.inherited(arguments);
                this.initAutoEnv();
                var existing = (this.structure && this.structure[0].cells[0]) ? 
                    this.structure[0].cells[0] : [];
                var fields = [];

                for(var f in this.sortedFieldList) {
                    var field = this.sortedFieldList[f];
                    if(!field || field.virtual) continue;
                    var entry = existing.filter(
                        function(i){return (i.field == field.name)})[0];
                    if(entry) entry.name = field.label;
                    else entry = {field:field.name, name:field.label};
                    fields.push(entry);
                    if(!entry.get) 
                        entry.get = openils.widget.AutoGrid.defaultGetter
                    if(!entry.width && this.defaultCellWidth)
                        entry.width = this.defaultCellWidth;
                }

                this.setStructure([{cells: [fields]}]);
                this.setStore(this.buildAutoStore());
                if(this.editOnEnter) 
                    this._applyEditOnEnter();
            },

            /* capture keydown and launch edit dialog on enter */
            _applyEditOnEnter : function() {

                this.onMouseOverRow = function(e) {};
                this.onMouseOutRow = function(e) {};
                this.onCellFocus = function(cell, rowIndex) { 
                    this.selection.deselectAll();
                    this.selection.select(this.focus.rowIndex);
                };

                dojo.connect(this, 'onRowDblClick',
                    function(e) {
                        this._drawEditDialog(this.selection.getFirstSelected(), this.focus.rowIndex);
                    }
                );

                dojo.connect(this, 'onKeyDown',
                    function(e) {
                        if(e.keyCode == dojo.keys.ENTER) {
                            this.selection.deselectAll();
                            this.selection.select(this.focus.rowIndex);
                            this._drawEditDialog(this.selection.getFirstSelected(), this.focus.rowIndex);
                        }
                    }
                );
            },

            _drawEditDialog : function(storeItem, rowIndex) {
                var grid = this;
                var fmObject = new fieldmapper[this.fmClass]().fromStoreItem(storeItem);
                var idents = grid.store.getIdentityAttributes();
                var dialog = new openils.widget.EditDialog({
                    fmObject:fmObject,
                    onPostSubmit : function() {
                        for(var i in fmObject._fields) {
                            var field = fmObject._fields[i];
                            if(idents.filter(function(j){return (j == field)})[0])
                                continue; // don't try to edit an identifier field
                            grid.store.setValue(storeItem, field, fmObject[field]());
                        }
                        dialog.destroy();
                        setTimeout(function(){
                            grid.views.views[1].getCellNode(rowIndex, 0).focus();},200);
                    },
                    onCancel : function() {
                        setTimeout(function(){
                            grid.views.views[1].getCellNode(rowIndex, 0).focus();},200);
                    }
                });
                dialog.editPane.fieldOrder = this.fieldOrder;
                dialog.editPane.mode = 'update';
                dialog.startup();
                dialog.show();
            },

            showCreateDialog : function() {
                var grid = this;
                var dialog = new openils.widget.EditDialog({
                    fmClass : this.fmClass,
                    onPostSubmit : function(r) {
                        var fmObject = openils.Util.readResponse(r);
                        if(fmObject) 
                            grid.store.newItem(fmObject.toStoreItem());
                        dialog.destroy();
                        setTimeout(function(){
                            grid.selection.select(grid.rowCount-1);
                            grid.views.views[1].getCellNode(grid.rowCount-1, 1).focus();
                        },200);
                    },
                });
                dialog.editPane.fieldOrder = this.fieldOrder;
                dialog.editPane.mode = 'create';
                dialog.startup();
                dialog.show();
            },

            loadAll : function(opts) {
                dojo.require('openils.PermaCrud');
                if(!opts) opts = {};
                var self = this;
                opts = dojo.mixin(opts, {
                    async : true,
                    streaming : true,
                    onresponse : function(r) {
                        var item = openils.Util.readResponse(r);
                        self.store.newItem(item.toStoreItem());
                    }
                });
                new openils.PermaCrud().retrieveAll(this.fmClass, opts);
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

