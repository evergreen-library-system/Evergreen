if(!dojo._hasResource['openils.widget.AutoGrid']) {
    dojo.provide('openils.widget.AutoGrid');
    dojo.require('dojox.grid.DataGrid');
    dojo.require('openils.widget.AutoWidget');
    dojo.require('openils.widget.AutoFieldWidget');
    dojo.require('openils.widget.EditPane');
    dojo.require('openils.widget.EditDialog');
    dojo.require('openils.Util');

    dojo.declare(
        'openils.widget.AutoGrid',
        [dojox.grid.DataGrid, openils.widget.AutoWidget],
        {

            /* if true, pop up an edit dialog when user hits Enter on a give row */
            editOnEnter : false, 
            defaultCellWidth : null,
            editStyle : 'dialog',
            suppressFields : null,

            /* by default, don't show auto-generated (sequence) fields */
            showSequenceFields : false, 

            startup : function() {
                this.selectionMode = 'single';
                this.inherited(arguments);
                this.initAutoEnv();
                this.setStructure(this._compileStructure());
                this.setStore(this.buildAutoStore());
                this.overrideEditWidgets = {};
                this.overrideEditWidgetClass = {};
                if(this.editOnEnter) 
                    this._applyEditOnEnter();
                else if(this.singleEditStyle) 
                    this._applySingleEditStyle();
            },

            _compileStructure : function() {
                var existing = (this.structure && this.structure[0].cells[0]) ? 
                    this.structure[0].cells[0] : [];
                var fields = [];

                var self = this;
                function pushEntry(entry) {
                    if(self.suppressFields) {
                        if(dojo.indexOf(self.suppressFields, entry.field) != -1)
                            return;
                    }
                    if(!entry.get) 
                        entry.get = openils.widget.AutoGrid.defaultGetter
                    if(!entry.width && self.defaultCellWidth)
                        entry.width = self.defaultCellWidth;
                    fields.push(entry);
                }

                if(!this.fieldOrder) {
                    /* no order defined, start with any explicit grid fields */
                    for(var e in existing) {
                        var entry = existing[e];
                        var field = this.fmIDL.fields.filter(
                            function(i){return (i.name == entry.field)})[0];
                        if(field) entry.name = entry.name || field.label;
                        pushEntry(entry);
                    }
                }

                for(var f in this.sortedFieldList) {
                    var field = this.sortedFieldList[f];
                    if(!field || field.virtual) continue;
                    
                    // field was already added above
                    if(fields.filter(function(i){return (i.field == field.name)})[0]) 
                        continue;

                    if(!this.showSequenceFields && field.name == this.fmIDL.pkey && this.fmIDL.pkey_sequence)
                        continue; 
                    var entry = existing.filter(function(i){return (i.field == field.name)})[0];
                    if(entry) entry.name = field.label;
                    else entry = {field:field.name, name:field.label};
                    pushEntry(entry);
                }

                if(this.fieldOrder) {
                    /* append any explicit non-IDL grid fields to the end */
                    for(var e in existing) {
                        var entry = existing[e];
                        var field = fields.filter(
                            function(i){return (i.field == entry.field)})[0];
                        if(field) continue; // don't duplicate
                        pushEntry(entry);
                    }
                }


                return [{cells: [fields]}];
            },

            _applySingleEditStyle : function() {
                this.onMouseOverRow = function(e) {};
                this.onMouseOutRow = function(e) {};
                this.onCellFocus = function(cell, rowIndex) { 
                    this.selection.deselectAll();
                    this.selection.select(this.focus.rowIndex);
                };
            },

            /* capture keydown and launch edit dialog on enter */
            _applyEditOnEnter : function() {
                this._applySingleEditStyle();

                dojo.connect(this, 'onRowDblClick',
                    function(e) {
                        if(this.editStyle == 'pane')
                            this._drawEditPane(this.selection.getFirstSelected(), this.focus.rowIndex);
                        else
                            this._drawEditDialog(this.selection.getFirstSelected(), this.focus.rowIndex);
                    }
                );

                dojo.connect(this, 'onKeyDown',
                    function(e) {
                        if(e.keyCode == dojo.keys.ENTER) {
                            this.selection.deselectAll();
                            this.selection.select(this.focus.rowIndex);
                            if(this.editStyle == 'pane')
                                this._drawEditPane(this.selection.getFirstSelected(), this.focus.rowIndex);
                            else
                                this._drawEditDialog(this.selection.getFirstSelected(), this.focus.rowIndex);
                        }
                    }
                );
            },

            _makeEditPane : function(storeItem, rowIndex, onPostSubmit, onCancel) {
                var grid = this;
                var fmObject = new fieldmapper[this.fmClass]().fromStoreItem(storeItem);
                var idents = grid.store.getIdentityAttributes();

                var pane = new openils.widget.EditPane({
                    fmObject:fmObject,
                    overrideWidgets : this.overrideEditWidgets,
                    overrideWidgetClass : this.overrideEditWidgetClass,
                    onPostSubmit : function() {
                        for(var i in fmObject._fields) {
                            var field = fmObject._fields[i];
                            if(idents.filter(function(j){return (j == field)})[0])
                                continue; // don't try to edit an identifier field
                            grid.store.setValue(storeItem, field, fmObject[field]());
                        }
                        if(self.onPostUpdate)
                            self.onPostUpdate(storeItem, rowIndex);
                        setTimeout(
                            function(){
                                try { 
                                    grid.views.views[0].getCellNode(rowIndex, 0).focus(); 
                                } catch (E) {}
                            },200
                        );
                        if(onPostSubmit) onPostSubmit();
                    },
                    onCancel : function() {
                        setTimeout(function(){
                            grid.views.views[0].getCellNode(rowIndex, 0).focus();},200);
                        if(onCancel) onCancel();
                    }
                });

                pane.fieldOrder = this.fieldOrder;
                pane.mode = 'update';
                return pane;
            },

            _makeCreatePane : function(onPostSubmit, onCancel) {
                var grid = this;
                var pane = new openils.widget.EditPane({
                    fmClass : this.fmClass,
                    overrideWidgets : this.overrideEditWidgets,
                    overrideWidgetClass : this.overrideEditWidgetClass,
                    onPostSubmit : function(r) {
                        var fmObject = openils.Util.readResponse(r);
                        if(fmObject) 
                            grid.store.newItem(fmObject.toStoreItem());
                        if(grid.onPostCreate)
                            grid.onPostCreate(fmObject);
                        setTimeout(function(){
                            try {
                                grid.selection.select(grid.rowCount-1);
                                grid.views.views[0].getCellNode(grid.rowCount-1, 1).focus();
                            } catch (E) {}
                        },200);
                        if(onPostSubmit)
                            onPostSubmit();
                    },
                    onCancel : function() {
                        if(onCancel) onCancel();
                    }
                });
                pane.fieldOrder = this.fieldOrder;
                pane.mode = 'create';
                return pane;
            },

            // .startup() is called within
            _makeClonePane : function(storeItem, rowIndex, onPostSubmit, onCancel) {
                var clonePane = this._makeCreatePane(onPostSubmit, onCancel);
                var origPane = this._makeEditPane(this.selection.getFirstSelected(), this.focus.rowIndex);
                clonePane.startup();
                origPane.startup();
                dojo.forEach(origPane.fieldList,
                    function(field) {
                        if(field.widget.widget.attr('disabled')) return;
                        var w = clonePane.fieldList.filter(
                            function(i) { return (i.name == field.name) })[0];
                        w.widget.baseWidgetValue(field.widget.widgetValue); // sync widgets
                        w.widget.onload = function(){w.widget.baseWidgetValue(field.widget.widgetValue)}; // async widgets
                    }
                );
                origPane.destroy();
                return clonePane;
            },


            _drawEditDialog : function(storeItem, rowIndex) {
                var self = this;
                var done = function() { self.hideDialog(); };
                var pane = this._makeEditPane(storeItem, rowIndex, done, done);
                this.editDialog = new openils.widget.EditDialog({editPane:pane});
                this.editDialog.startup();
                this.editDialog.show();
            },

            showCreateDialog : function() {
                var self = this;
                var done = function() { self.hideDialog(); };
                var pane = this._makeCreatePane(done, done);
                this.editDialog = new openils.widget.EditDialog({editPane:pane});
                this.editDialog.startup();
                this.editDialog.show();
            },

            _drawEditPane : function(storeItem, rowIndex) {
                var self = this;
                var done = function() { self.hidePane(); };
                dojo.style(this.domNode, 'display', 'none');
                this.editPane = this._makeEditPane(storeItem, rowIndex, done, done);
                this.editPane.startup();
                this.domNode.parentNode.insertBefore(this.editPane.domNode, this.domNode);
            },

            showClonePane : function(storeItem, rowIndex) {
                var self = this;
                var done = function() { self.hidePane(); };
                dojo.style(this.domNode, 'display', 'none');
                this.editPane = this._makeClonePane(storeItem, rowIndex, done, done);
                this.domNode.parentNode.insertBefore(this.editPane.domNode, this.domNode);
            },

            showCreatePane : function() {
                var self = this;
                var done = function() { self.hidePane(); };
                dojo.style(this.domNode, 'display', 'none');
                this.editPane = this._makeCreatePane(done, done);
                this.editPane.startup();
                this.domNode.parentNode.insertBefore(this.editPane.domNode, this.domNode);
            },

            hideDialog : function() {
                this.editDialog.hide(); 
                this.editDialog.destroy(); 
                delete this.editDialog;
            },

            hidePane : function() {
                this.domNode.parentNode.removeChild(this.editPane.domNode);
                this.editPane.destroy();
                delete this.editPane;
                dojo.style(this.domNode, 'display', 'block');
                this.update();
            },
            
            resetStore : function() {
                this.setStore(this.buildAutoStore());
            },

            loadAll : function(opts, search) {
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
                if(search)
                    new openils.PermaCrud().search(this.fmClass, search, opts);
                else
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

