if(!dojo._hasResource['openils.widget.AutoGrid']) {
    dojo.provide('openils.widget.AutoGrid');
    dojo.require('dojox.grid.DataGrid');
    dojo.require('dijit.layout.ContentPane');
    dojo.require('openils.widget.AutoWidget');
    dojo.require('openils.widget.AutoFieldWidget');
    dojo.require('openils.widget.EditPane');
    dojo.require('openils.widget.EditDialog');
    dojo.require('openils.widget.GridColumnPicker');
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
            hideSelector : false,
            selectorWidth : '1.5',
            showColumnPicker : false,
            columnPickerPrefix : null,
            displayLimit : 15,
            displayOffset : 0,
            showPaginator : false,

            /* by default, don't show auto-generated (sequence) fields */
            showSequenceFields : false, 

            startup : function() {
                this.selectionMode = 'single';
                this.sequence = openils.widget.AutoGrid.sequence++;
                openils.widget.AutoGrid.gridCache[this.sequence] = this;
                this.inherited(arguments);
                this.initAutoEnv();
                this.attr('structure', this._compileStructure());
                this.setStore(this.buildAutoStore());

                if(this.showColumnPicker) {
                    if(!this.columnPickerPrefix) {
                        console.error("No columnPickerPrefix defined");
                    } else {
                        var picker = new openils.widget.GridColumnPicker(
                            openils.User.authtoken, this.columnPickerPrefix, this);
                        if(openils.User.authtoken) {
                            picker.load();
                        } else {
                            openils.Util.addOnLoad(function() { picker.load() });
                        }
                    }
                }

                this.overrideEditWidgets = {};
                this.overrideEditWidgetClass = {};

                if(this.editOnEnter) 
                    this._applyEditOnEnter();
                else if(this.singleEditStyle) 
                    this._applySingleEditStyle();

                if(!this.hideSelector) {
                    dojo.connect(this, 'onHeaderCellClick', 
                        function(e) {
                            if(e.cell.index == 0)
                                this.toggleSelectAll();
                        }
                    );
                }

                if(this.showPaginator) {
                    var self = this;
                    this.paginator = new dijit.layout.ContentPane();


                    var back = dojo.create('a', {
                        innerHTML : 'Back', 
                        style : 'padding-right:6px;',
                        href : 'javascript:void(0);', 
                        onclick : function() { 
                            self.resetStore();
                            self.cachedQueryOpts.offset = self.displayOffset -= self.displayLimit;
                            self.loadAll(self.cachedQueryOpts, self.cachedQuerySearch);
                        }
                    });

                    var forw = dojo.create('a', {
                        innerHTML : 'Next', 
                        style : 'padding-right:6px;',
                        href : 'javascript:void(0);', 
                        onclick : function() { 
                            self.resetStore();
                            self.cachedQueryOpts.offset = self.displayOffset += self.displayLimit;
                            self.loadAll(self.cachedQueryOpts, self.cachedQuerySearch);
                        }
                    });

                    dojo.place(this.paginator.domNode, this.domNode, 'before');
                    dojo.place(back, this.paginator.domNode);
                    dojo.place(forw, this.paginator.domNode);
                    this.loadProgressIndicator = dojo.create('img', {
                        src:'/opac/images/progressbar_green.gif',
                        style:'height:16px;width:16px;'
                    });
                    dojo.place(this.loadProgressIndicator, this.paginator.domNode);
                }
            },

            /* Don't allow sorting on the selector column */
            canSort : function(rowIdx) {
                if(rowIdx == 1 && !this.hideSelector)
                    return false;
                return true;
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

                if(!this.hideSelector) {
                    // insert the selector column
                    pushEntry({
                        field : '+selector',
                        formatter : function(rowIdx) { return self._formatRowSelectInput(rowIdx); },
                        get : function(rowIdx, item) { if(item) return rowIdx; },
                        width : this.selectorWidth,
                        name : '&#x2713',
                        nonSelectable : true
                    });
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

                    var entry = existing.filter(function(i){return (i.field == field.name)})[0];
                    if(entry) {
                        entry.name = field.label;
                    } else {
                        // unless specifically requested, hide sequence fields
                        if(!this.showSequenceFields && field.name == this.fmIDL.pkey && this.fmIDL.pkey_sequence)
                            continue; 

                        entry = {field:field.name, name:field.label};
                    }
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

            toggleSelectAll : function() {
                var selected = this.getSelectedRows();
                for(var i = 0; i < this.rowCount; i++) {
                    if(selected[0])
                        this.deSelectRow(i);
                    else
                        this.selectRow(i);
                }
            },

            getSelectedRows : function() {
                var rows = []; 
                dojo.forEach(
                    dojo.query('[name=autogrid.selector]', this.domNode),
                    function(input) {
                        if(input.checked)
                            rows.push(input.getAttribute('row'));
                    }
                );
                return rows;
            },

            getFirstSelectedRow : function() {
                return this.getSelectedRows()[0];
            },

            getSelectedItems : function() {
                var items = [];
                var self = this;
                dojo.forEach(this.getSelectedRows(), function(idx) { items.push(self.getItem(idx)); });
                return items;
            },

            selectRow : function(rowIdx) {
                var inputs = dojo.query('[name=autogrid.selector]', this.domNode);
                for(var i = 0; i < inputs.length; i++) {
                    if(inputs[i].getAttribute('row') == rowIdx) {
                        if(!inputs[i].disabled)
                            inputs[i].checked = true;
                        break;
                    }
                }
            },

            deSelectRow : function(rowIdx) {
                var inputs = dojo.query('[name=autogrid.selector]', this.domNode);
                for(var i = 0; i < inputs.length; i++) {
                    if(inputs[i].getAttribute('row') == rowIdx) {
                        inputs[i].checked = false;
                        break;
                    }
                }
            },

            getAllObjects : function() {
                var objs = [];
                var self = this;
                this.store.fetch({
                    onComplete : function(list) {
                        dojo.forEach(list, 
                            function(item) {
                                objs.push(new fieldmapper[self.fmClass]().fromStoreItem(item));
                            }
                        )
                    }
                });
                return objs;
            },

            deleteSelected : function() {
                var items = this.getSelectedItems();
                var total = items.length;
                var self = this;
                dojo.require('openils.PermaCrud');
                var pcrud = new openils.PermaCrud();
                dojo.forEach(items,
                    function(item) {
                        var fmObject = new fieldmapper[self.fmClass]().fromStoreItem(item);
                        pcrud['delete'](fmObject, {oncomplete : function(r) { self.store.deleteItem(item) }});
                    }
                );
            },

            _formatRowSelectInput : function(rowIdx) {
                if(rowIdx === null || rowIdx === undefined) return '';
                var s = "<input type='checkbox' name='autogrid.selector' row='" + rowIdx + "'";
                if(this.disableSelectorForRow && this.disableSelectorForRow(rowIdx)) 
                    s += " disabled='disabled'";
                return s + "/>";
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
                    disableWidgetTest : this.disableWidgetTest,
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
                    disableWidgetTest : this.disableWidgetTest,
                    onPostSubmit : function(r) {
                        var fmObject = openils.Util.readResponse(r);
                        if(grid.onPostCreate)
                            grid.onPostCreate(fmObject);
                        if(fmObject) 
                            grid.store.newItem(fmObject.toStoreItem());
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
                var origPane = this._makeEditPane(storeItem, rowIndex);
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
                if(this.onEditPane) this.onEditPane(this.editPane);
            },

            showClonePane : function() {
                var self = this;
                var done = function() { self.hidePane(); };
                var row = this.getFirstSelectedRow();
                if(!row) return;
                dojo.style(this.domNode, 'display', 'none');
                this.editPane = this._makeClonePane(this.getItem(row), row, done, done);
                this.domNode.parentNode.insertBefore(this.editPane.domNode, this.domNode);
                if(this.onEditPane) this.onEditPane(this.editPane);
            },

            showCreatePane : function() {
                var self = this;
                var done = function() { self.hidePane(); };
                dojo.style(this.domNode, 'display', 'none');
                this.editPane = this._makeCreatePane(done, done);
                this.editPane.startup();
                this.domNode.parentNode.insertBefore(this.editPane.domNode, this.domNode);
                if(this.onEditPane) this.onEditPane(this.editPane);
            },

            hideDialog : function() {
                this.editDialog.hide(); 
                this.editDialog.destroy(); 
                delete this.editDialog;
                this.update();
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
                if(this.loadProgressIndicator)
                    dojo.style(this.loadProgressIndicator, 'visibility', 'visible');
                var self = this;
                opts = dojo.mixin(
                    {limit : this.displayLimit, offset : this.displayOffset}, 
                    opts || {}
                );
                opts = dojo.mixin(opts, {
                    async : true,
                    streaming : true,
                    onresponse : function(r) {
                        var item = openils.Util.readResponse(r);
                        self.store.newItem(item.toStoreItem());
                    },
                    oncomplete : function() {
                        if(self.loadProgressIndicator) 
                            dojo.style(self.loadProgressIndicator, 'visibility', 'hidden');
                    }
                });

                this.cachedQuerySearch = search;
                this.cachedQueryOpts = opts;
                if(search)
                    new openils.PermaCrud().search(this.fmClass, search, opts);
                else
                    new openils.PermaCrud().retrieveAll(this.fmClass, opts);
            }
        } 
    );

    // static ID generater seed
    openils.widget.AutoGrid.sequence = 0;
    openils.widget.AutoGrid.gridCache = {};

    openils.widget.AutoGrid.markupFactory = dojox.grid.DataGrid.markupFactory;

    openils.widget.AutoGrid.defaultGetter = function(rowIndex, item) {
        if(!item) return '';
        var val = this.grid.store.getValue(item, this.field);
        var autoWidget = new openils.widget.AutoFieldWidget({
            fmClass: this.grid.fmClass,
            fmField: this.field,
            widgetValue : val,
            readOnly : true
        });

        var _this = this;
        autoWidget.build(
            function(w, ww) {
                var node = _this.grid.getCell(_this.index).view.getCellNode(rowIndex, _this.index);
                if(node) {
                    node.innerHTML = ww.getDisplayString();
                }
            }
        );

        return autoWidget.getDisplayString();
    }
}

