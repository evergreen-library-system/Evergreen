if(!dojo._hasResource['openils.widget.AutoGrid']) {
    dojo.provide('openils.widget.AutoGrid');
    dojo.require('dojox.grid.DataGrid');
    dojo.require('dijit.layout.ContentPane');
    dojo.require('openils.widget.AutoWidget');
    dojo.require('openils.widget.AutoFieldWidget');
    dojo.require('openils.widget.EditPane');
    dojo.require('openils.widget.EditDialog');
    dojo.require('openils.widget.GridColumnPicker');
    dojo.require('openils.widget._GridHelperColumns');
    dojo.require('openils.Util');

    dojo.declare(
        'openils.widget.AutoGrid',
        [dojox.grid.DataGrid, openils.widget.AutoWidget, openils.widget._GridHelperColumns],
        {

            /* if true, pop up an edit dialog when user hits Enter on a give row */
            editPaneOnSubmit : null,
            onPostSubmit : null, // called after any CRUD actions are complete
            createPaneOnSubmit : null,
            editOnEnter : false, 
            defaultCellWidth : null,
            editStyle : 'dialog',
            editReadOnly : false,
            suppressFields : null,
            suppressEditFields : null,
            suppressFilterFields : null,
            showColumnPicker : false,
            columnPersistKey : null,
            displayLimit : 15,
            displayOffset : 0,
            requiredFields : null,
            hidePaginator : false,
            showLoadFilter : false,
            onItemReceived : null,
            suppressLinkedFields : null, // list of fields whose linked display data should not be fetched from the server

            /* by default, don't show auto-generated (sequence) fields */
            showSequenceFields : false, 

            startup : function() {
                var _this = this;
                this.selectionMode = 'single';
                this.sequence = openils.widget.AutoGrid.sequence++;
                openils.widget.AutoGrid.gridCache[this.sequence] = this;
                this.inherited(arguments);
                this.initAutoEnv();

                this.setStructure(this._compileStructure());
                this._startupGridHelperColumns();
                this.setStructure(this.structure); // required after _startupGridHelper()

                this.setStore(this.buildAutoStore());
                this.cachedQueryOpts = {};
                this._showing_create_pane = false;
                this.overrideEditWidgets = {};
                this.overrideEditWidgetClass = {};
                this.overrideWidgetArgs = {};

                if(this.editOnEnter) 
                    this._applyEditOnEnter();
                else if(this.singleEditStyle) 
                    this._applySingleEditStyle();

                if(!this.hidePaginator) {
                    var self = this;
                    this.paginator = new dijit.layout.ContentPane();


                    var back = dojo.create('a', {
                        innerHTML : 'Back',  // TODO i18n
                        style : 'padding-right:6px;',
                        href : 'javascript:void(0);', 
                        onclick : function() { 
                            self.cachedQueryOpts.offset = self.displayOffset -= self.displayLimit;
                            if(self.displayOffset < 0)
                                self.cachedQueryOpts.offset = self.displayOffset = 0;
                            self.refresh();
                        }
                    });

                    var forw = dojo.create('a', {
                        innerHTML : 'Next',  // TODO i18n
                        style : 'padding-right:6px;',
                        href : 'javascript:void(0);', 
                        onclick : function() { 
                            self.cachedQueryOpts.offset = self.displayOffset += self.displayLimit;
                            self.refresh();
                        }
                    });

                    dojo.place(this.paginator.domNode, this.domNode, 'before');
                    dojo.place(back, this.paginator.domNode);
                    dojo.place(forw, this.paginator.domNode);

                    if(this.showLoadFilter) {
                        dojo.require('openils.widget.PCrudFilterDialog');
                        dojo.place(
                            dojo.create('a', {
                                innerHTML : 'Filter', // TODO i18n
                                style : 'padding-right:6px;',
                                href : 'javascript:void(0);', 
                                onclick : function() { 
                                    if (!self.filterDialog) {

                                        self.filterDialog = new openils.widget.PCrudFilterDialog(
                                            {fmClass:self.fmClass, suppressFilterFields:self.suppressFilterFields})

                                        self.filterDialog.onApply = function(filter) {
                                            self.cachedQuerySearch = dojo.mixin( filter, self.preFilterSearch );
                                            self.resetStore();
                                            self.loadAll(
                                                dojo.mixin( { offset : 0 }, self.cachedQueryOpts ),
                                                self.cachedQuerySearch,
                                                true
                                            );
                                        };

                                        self.filterDialog.startup();
                                    }
                                    self.filterDialog.show();
                                }
                            }),
                            this.paginator.domNode
                        );
                    }

                    // progress image
                    this.loadProgressIndicator = dojo.create('img', {
                        src:'/opac/images/progressbar_green.gif', // TODO configured path
                        style:'height:16px;width:16px;'
                    });
                    dojo.place(this.loadProgressIndicator, this.paginator.domNode);
                }
            },

            hideLoadProgressIndicator : function() {
                dojo.style(this.loadProgressIndicator, 'visibility', 'hidden');
            },

            showLoadProgressIndicator : function() {
                dojo.style(this.loadProgressIndicator, 'visibility', 'visible');
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

                    var entry = existing.filter(function(i){return (i.field == field.name)})[0];
                    if(entry) {
                        entry.name = entry.name || field.label;
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

            /**
             * @return {Array} List of every fieldmapper object in the data store
             */
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

            /**
             * Deletes the underlying object for all selected rows
             */
            deleteSelected : function() {
                var items = this.getSelectedItems();
                var total = items.length;
                var self = this;
                dojo.require('openils.PermaCrud');
                dojo.forEach(items,
                    function(item) {
                        var fmObject = new fieldmapper[self.fmClass]().fromStoreItem(item);
                        new openils.PermaCrud()['eliminate'](
                            fmObject, {
                                oncomplete : function(r) {
                                    self.store.deleteItem(item);
                                    if (--total < 1 && self.onPostSubmit) {
                                        self.onPostSubmit();
                                    }
                                }
                            }
                        );
                    }
                );
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
                    hideSaveButton : this.editReadOnly,
                    readOnly : this.editReadOnly,
                    overrideWidgets : this.overrideEditWidgets,
                    overrideWidgetClass : this.overrideEditWidgetClass,
                    overrideWidgetArgs : this.overrideWidgetArgs,
                    disableWidgetTest : this.disableWidgetTest,
                    requiredFields : this.requiredFields,
                    suppressFields : this.suppressEditFields,
                    onPostSubmit : function() {
                        for(var i in fmObject._fields) {
                            var field = fmObject._fields[i];
                            if(idents.filter(function(j){return (j == field)})[0])
                                continue; // don't try to edit an identifier field
                            grid.store.setValue(storeItem, field, fmObject[field]());
                        }
                        if(grid.onPostUpdate)
                            grid.onPostUpdate(storeItem, rowIndex);
                        setTimeout(
                            function(){
                                try { 
                                    grid.views.views[0].getCellNode(rowIndex, 0).focus(); 
                                } catch (E) {}
                            },200
                        );
                        if(onPostSubmit) 
                            onPostSubmit();
                        if (grid.onPostSubmit)
                            grid.onPostSubmit();

                    },
                    onCancel : function() {
                        setTimeout(function(){
                            grid.views.views[0].getCellNode(rowIndex, 0).focus();},200);
                        if(onCancel) onCancel();
                    }
                });

                if (typeof this.editPaneOnSubmit == "function")
                    pane.onSubmit = this.editPaneOnSubmit;
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
                    overrideWidgetArgs : this.overrideWidgetArgs,
                    disableWidgetTest : this.disableWidgetTest,
                    requiredFields : this.requiredFields,
                    suppressFields : this.suppressEditFields,
                    onPostSubmit : function(req, cudResults) {
                        var fmObject = cudResults[0];
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
                            onPostSubmit(fmObject);
                        if (grid.onPostSubmit)
                            grid.onPostSubmit();
                    },
                    onCancel : function() {
                        if(onCancel) onCancel();
                    }
                });
                if (typeof this.createPaneOnSubmit == "function")
                    pane.onSubmit = this.createPaneOnSubmit;
                pane.fieldOrder = this.fieldOrder;
                pane.mode = 'create';
                return pane;
            },

            /**
             * Creates an EditPane with a copy of the data from the provided store
             * item for cloning said item
             * @param {Object} storeItem Dojo data item
             * @param {Number} rowIndex The Grid row index of the item to be cloned
             * @param {Function} onPostSubmit Optional callback for post-submit behavior
             * @param {Function} onCancel Optional callback for clone cancelation
             * @return {Object} The clone EditPane
             */
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
                        w.widget.baseWidgetValue(field.widget.widget.attr('value')); // sync widgets
                        w.widget.onload = function(){w.widget.baseWidgetValue(field.widget.widget.attr('value'))}; // async widgets
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
                if(this.onEditPane) this.onEditPane(pane);
            },

            /**
             * Generates an EditDialog for object creation and displays it to the user
             */
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

            showClonePane : function(onPostSubmit) {
                var self = this;
                var done = function() { self.hidePane(); };

                                    
                var row = this.getFirstSelectedRow();
                if(!row) return;

                var postSubmit = (onPostSubmit) ? 
                    function(result) { onPostSubmit(self.getItem(row), result); self.hidePane(); } :
                    done;

                dojo.style(this.domNode, 'display', 'none');
                this.editPane = this._makeClonePane(this.getItem(row), row, postSubmit, done);
                this.domNode.parentNode.insertBefore(this.editPane.domNode, this.domNode);
                if(this.onEditPane) this.onEditPane(this.editPane);
            },

            showCreatePane : function() {
                if (this._showing_create_pane)
                    return;
                this._showing_create_pane = true;

                var self = this;
                var done = function() {
                    self._showing_create_pane = false;
                    self.hidePane();
                };
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

            refresh : function(opts, search) {
                opts = opts || this.cachedQueryOpts;
                search = search || this.cachedQuerySearch;
                this.resetStore();
                if (this.dataLoader)
                    this.dataLoader()
                else
                    this._loadAll(opts, search);
            },

            // called after a sort change occurs within the column picker
            cpSortHandler : function(fields) {
                console.log("AutoGrod cpSortHandler(): " + js2JSON(fields));
                // user-defined sort handler
                if (this.onSortChange) { 
                    this.onSortChange(fields)

                // default sort handler
                } else { 
                    if (!this.cachedQueryOpts) 
                        this.cachedQueryOpts = {};
                    var order_by = '';
                    dojo.forEach(fields, function(f) {
                        if (order_by) order_by += ',';
                        order_by += f.field + ' ' + f.direction
                    });
                    this.cachedQueryOpts.order_by = {};
                    this.cachedQueryOpts.order_by[this.fmClass] = order_by;
                    this.refresh();
                }
            },

            loadAll : function(opts, search, filter_triggered) {
                var _this = this;

                // first we have to load the column picker to determine the sort fields.
               
                if(this.showColumnPicker && !this.columnPicker) {
                    if(!this.columnPersistKey) {
                        console.error("No columnPersistKey defined");
                        this.columnPicker = {};
                    } else {
                        this.columnPicker = new openils.widget.GridColumnPicker(
                            openils.User.authtoken, this.columnPersistKey, this);
                        this.columnPicker.onSortChange = function(fields) {_this.cpSortHandler(fields)};
                        this.columnPicker.onLoad = function(cpOpts) {
                            _this.cachedQueryOpts = opts;
                            _this.cachedQuerySearch = search;
                            _this.cpSortHandler(cpOpts.sortFields); // calls refresh() -> _loadAll()
                        };
                        this.columnPicker.load();
                        return;
                    }
                }

                // column picker not wanted or already loaded
                this._loadAll(opts, search, filter_triggered);
            },

            _loadAll : function(opts, search, filter_triggered) {
                var self = this;

                dojo.require('openils.PermaCrud');
                if(this.loadProgressIndicator)
                    dojo.style(this.loadProgressIndicator, 'visibility', 'visible');
                opts = dojo.mixin(
                    {limit : this.displayLimit, offset : this.displayOffset}, 
                    opts || {}
                );
                opts = dojo.mixin(opts, {
                    async : true,
                    streaming : true,
                    onresponse : function(r) {
                        var item = openils.Util.readResponse(r);
                        if (self.onItemReceived) 
                            self.onItemReceived(item);
                        self.store.newItem(item.toStoreItem());
                    },
                    oncomplete : function() {
                        if(self.loadProgressIndicator) 
                            dojo.style(self.loadProgressIndicator, 'visibility', 'hidden');
                    }
                });

                this.cachedQuerySearch = search;
                this.cachedQueryOpts = opts;

                // retain the most recent external loadAll 
                if (!filter_triggered || !this.preFilterSearch)
                    this.preFilterSearch = dojo.clone( this.cachedQuerySearch );

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
        if(!this.grid.overrideWidgetArgs[this.field])
            this.grid.overrideWidgetArgs[this.field] = {};
        var val = this.grid.store.getValue(item, this.field);
        var autoWidget = new openils.widget.AutoFieldWidget(dojo.mixin({
            fmClass: this.grid.fmClass,
            fmField: this.field,
            widgetValue : val,
            readOnly : true,
            forceSync : true, // prevents many simultaneous requests for the same data
            suppressLinkedFields : this.grid.suppressLinkedFields
        },this.grid.overrideWidgetArgs[this.field]));

        autoWidget.build();

        /*
        // With proper caching, this should not be necessary to prevent grid render flickering
        var _this = this;
        autoWidget.build(
            function(w, ww) {
                try {
                    var node = _this.grid.getCell(_this.index).view.getCellNode(rowIndex, _this.index);
                    if(node) 
                        node.innerHTML = ww.getDisplayString();
                } catch(E) {}
            }
        );
        */

        return autoWidget.getDisplayString();
    };

    openils.widget.AutoGrid.orgUnitGetter = function(rowIndex, item) {
        if (!item) return "";

        var aou_id = this.grid.store.getValue(item, this.field);
        if (aou_id)
            return fieldmapper.aou.findOrgUnit(aou_id).shortname();
        else
            return "";
    };
}

