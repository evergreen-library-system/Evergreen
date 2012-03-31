/* ---------------------------------------------------------------------------
 * Copyright (C) 2008  Georgia Public Library Service
 * Bill Erickson <erickson@esilibrary.com>
 *
 * This program is free software; you can redistribute it and/or
 * modify it under the terms of the GNU General Public License
 * as published by the Free Software Foundation; either version 2
 * of the License, or (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 * ---------------------------------------------------------------------------
 */


if(!dojo._hasResource["openils.widget.GridColumnPicker"]) {
    dojo.provide('openils.widget.GridColumnPicker');

    dojo.require('dijit.Dialog');
    dojo.require('dijit.form.Button');
    dojo.require('dijit.form.NumberSpinner');
    dojo.require('openils.User');
    dojo.require('openils.Event');
    dojo.require('openils.Util');
    dojo.require('fieldmapper.Fieldmapper');


    dojo.declare('openils.widget.GridColumnPicker', null, {

        USER_PERSIST_SETTING : 'ui.grid_columns',

        constructor : function (authtoken, persistKey, grid, structure) {
            var _this = this;
            this.grid = grid;
            this.persistKey = this.USER_PERSIST_SETTING+'.'+persistKey;
            this.authtoken = authtoken || openils.User.authtoken;
            this.structure = structure || this.grid.structure;
            this.cells = this.structure[0].cells[0].slice();

            this.dialog = this.buildDialog();
            this.dialogTable = this.dialog.containerNode.getElementsByTagName('tbody')[0];

            // replace: called after any sort changes
            this.onSortChange = function(list) {console.log('onSortChange()')}
            // replace:  called after user settings are first retrieved
            this.onLoad = function(opts) {console.log('onLoad()')};

            // internal onload handler
            this.loaded = false;
            this._onLoad = function(opts) {_this.loaded = true; _this.onLoad(opts)};

            this.grid.onHeaderContextMenu = function(e) { 
                _this.build();
                _this.dialog.show(); 
                dojo.stopEvent(e);
            };
        },

        /** Loads any grid column label changes, clears any 
         * non-visible fields from the structure, and passes 
         * the structure back to the grid to force a UI refresh.
         */
        reloadStructure : function() {

            // update our copy of the column labels
            var _this = this;
            dojo.forEach(
                this.grid.structure[0].cells[0],
                function(gcell) {
                    var cell = _this.cells.filter(
                        function(c) { return c.field == gcell.field }
                    )[0];
                    cell.name = gcell.name;
                }
            );

            this.pruneInvisibleFields();
            this.grid.setStructure(this.structure);
        },


        // determine the visible sorting from the 
        // view and update our list of cells to match
        refreshCells : function() {
            var cells = this.cells;
            this.cells = [];
            var _this = this;

            dojo.forEach(
                 _this.grid.views.views[0].structure.cells[0],
                 function(vCell) {
                    for (var i = 0; i < cells.length; i++) {
                        if (cells[i].field == vCell.field) {
                            cells[i]._visible = true;
                            _this.cells.push(cells[i]);
                            break;
                        }
                    }
                }
            );

            // Depending on how the grid structure is built, there may be
            // cells in the structure that are not yet in the view.  Push
            // any remaining cells onto the end.
            dojo.forEach(
                cells,
                function(cell) {
                    existing = _this.cells.filter(function(s){return s.field == cell.field})[0]
                    if (!existing) {
                        cell._visible = false;
                        _this.cells.push(cell);
                    }
                }
            );
        },

        buildDialog : function() {
            var self = this;
            
            // TODO i18n

            var dialog = new dijit.Dialog({title : 'Column Picker'});
            var table = dojo.create('table', {'class':'oils-generic-table', innerHTML : 
                "<table><thead><tr><th width='30%'>Column</th><th width='23%'>Display</th>" +
                "<th width='23%'>Auto Width</th><th width='23%'>Sort Priority</th></tr></thead>" +
                "<tbody />"});

            var tDiv = dojo.create('div');
            tDiv.appendChild(table);

            var bDiv = dojo.create('div', {style : 'text-align:right; width:100%;',
                innerHTML : "<span name='cancel_button'></span><span name='save_button'></span>"});

            var textDiv = dojo.create('div', {style : 'padding:5px; margin-top:5px; border-top:1px solid #333', 
                innerHTML :
                    "<i>A Sort Priority of '0' means no sorting is applied.<br/>" +
                    "<i>Apply a negative Sort Priority for descending sort."});
            
            var wrapper = dojo.create('div');
            wrapper.appendChild(tDiv);
            wrapper.appendChild(textDiv);
            wrapper.appendChild(bDiv);
            dialog.containerNode.appendChild(wrapper);

            var button = new dijit.form.Button({label:'Save'}, 
                dojo.query('[name=save_button]', bDiv)[0]);
            button.onClick = function() { dialog.hide(); self.update(true); };

            button = new dijit.form.Button({label:'Cancel'}, 
                dojo.query('[name=cancel_button]', bDiv)[0]);
            button.onClick = function() { dialog.hide(); };

            return dialog;
        },

        // builds the column-picker dialog table
        build : function() {
            this.refreshCells();
            var rows = dojo.query('tr', this.dialogTable);

            for(var i = 0; i < rows.length; i++) {
                if(rows[i].getAttribute('picker'))
                    this.dialogTable.removeChild(rows[i]);
            }

            rows = dojo.query('tr', this.dialogTable);
            var lastChild = null;
            if(rows.length > 0)
                lastChild = rows[rows.length-1];

            for(var i = 0; i < this.cells.length; i++) {
                // setting table.innerHTML breaks stuff, so do it the hard way
                var cell = this.cells[i];
                tr = document.createElement('tr');
                tr.setAttribute('picker', 'picker');
                td0 = document.createElement('td');
                td1 = document.createElement('td');
                td2 = document.createElement('td');
                td3 = document.createElement('td');

                ipt = document.createElement('input');
                ipt.setAttribute('type', 'checkbox');
                ipt.setAttribute('name', 'selector');

                ipt2 = document.createElement('input');
                ipt2.setAttribute('type', 'checkbox');
                ipt2.setAttribute('name', 'width');

                ipt3 = document.createElement('div');

                if (cell.nonSelectable) {
                    ipt.setAttribute('checked', 'checked');
                    ipt.setAttribute('disabled', true);
                    ipt2.setAttribute('disabled', true);

                } else {
                    if (cell._visible) {
                        ipt.setAttribute('checked', 'checked');
                        if (cell.width == 'auto') 
                            ipt2.setAttribute('checked', 'checked');
                    } else {
                        ipt.removeAttribute('checked');
                    }
                }

                if (cell.field == '+selector') {
                    // pick up the unescaped unicode checkmark char
                    td0.innerHTML = cell.name;
                } else {
                    td0.appendChild(document.createTextNode(cell.name));
                }
                td1.appendChild(ipt);
                td2.appendChild(ipt2);
                td3.appendChild(ipt3);
                tr.appendChild(td0);
                tr.appendChild(td1);
                tr.appendChild(td2);
                tr.appendChild(td3);

                if(lastChild)
                    this.dialogTable.insertBefore(tr, lastChild);
                else
                    this.dialogTable.appendChild(tr);

                if (this.grid.canSort(
                    i + 1,  /* column index is 1-based */
                    true    /* skip structure test (API abuse) */
                )) { 

                    /* Ugly kludge. When using with FlattenerGrid the
                     * conditional is needed. Shouldn't hurt usage with
                     * AutoGrid. */
                    if (typeof cell.fsort == "undefined" || cell.fsort) {
                        // must be added after its parent node is inserted into the DOM.
                        var ns = new dijit.form.NumberSpinner(
                            {   constraints : {places : 0}, 
                                value : cell._sort || 0,
                                style : 'width:4em',
                                name : 'sort',
                            }, ipt3
                        );
                    }
                }
            }
        },

        // update the grid based on the items selected in the picker dialog
        update : function(persist) {
            var rows = dojo.query('[picker=picker]', this.dialogTable);
            var _this = this;
            var displayCells = [];
            var sortUpdated = false;

            for (var i = 0; i < rows.length; i++) {
                var row = rows[i];
                var selector = dojo.query('[name=selector]', row)[0];
                var width = dojo.query('[name=width]', row)[0];
                var sort = dojo.query('[name=sort]', row)[0];
                var cell = this.cells[i]; // index should match dialog

                if (sort && cell._sort != sort.value) {
                    sortUpdated = true;
                    cell._sort = sort.value;
                }

                if (selector.checked) {
                    cell._visible = true;
                    if (width.checked) {
                        cell.width = 'auto';
                    } else if(cell.width == 'auto') {
                        delete cell.width;
                    }
                    displayCells.push(cell);

                } else {
                    cell._visible = false;
                    delete cell.width;
                }
            }

            if (sortUpdated && this.onSortChange) 
                this.onSortChange(this.buildSortList());

            this.structure[0].cells[0] = displayCells;
            this.grid.setStructure(this.structure);
            this.grid.update();

            if (persist) this.persist(true);
        },

        // extract cells that have sorting applied, order lowest to highest
        buildSortList : function() {
            var sortList = this.cells.filter(
                function(cella) { return Number(cella._sort) }
            ).sort( 
                function(a, b) { 
                    if (Math.abs(a._sort) < Math.abs(b._sort)) return -1; 
                    return 1; 
                }
            );

            return sortList.map(function(f){
                var dir = f._sort < 0 ? 'desc' : 'asc';
                return {field : f.field, direction : dir};
            });
        },

        // save me as a user setting
        persist : function(noRefresh) {
            var list = [];
            var autos = [];
            if (!noRefresh) this.refreshCells();

            for(var i = 0; i < this.cells.length; i++) {
                var cell = this.cells[i];
                if (cell._visible) {
                    list.push(cell.field);
                    if(cell.width == 'auto')
                        autos.push(cell.field);
                } 
            }

            var setting = {};
            setting[this.persistKey] = {
                'columns' : list, 
                'auto' : autos,
                'sort' : this.buildSortList().map(function(f){return f.field})
            };

            var _this = this;
            fieldmapper.standardRequest(
                ['open-ils.actor', 'open-ils.actor.patron.settings.update'],
                {   async: true,
                    params: [this.authtoken, null, setting],
                    oncomplete: function(r) {
                        var stat = openils.Util.readResponse(r);
                    },
                    onmethoderror : function() {},
                    onerror : function() { 
                        console.log("No user setting '" + _this.persistKey + "' configured.  Cannot persist") 
                    }
                }
            );
        }, 

        loadColsFromSetting : function(setting) {
            var _this = this;
            this.setting = setting;
            var displayCells = [];
            
            // new component, existing settings may not have this
            if (!setting.sort) setting.sort = [];

            dojo.forEach(setting.columns,
                function(col) {
                    var cell = _this.cells.filter(function(c){return c.field == col})[0];
                    if (cell) {
                        cell._visible = true;
                        displayCells.push(cell);

                        if(setting.auto.indexOf(cell.field) > -1) {
                            cell.width = 'auto';
                        } else {
                            if(cell.width == 'auto')
                                delete cell.width;
                        }
                        cell._sort = setting.sort.indexOf(cell.field) + 1;

                    } else {
                        console.log('Unknown setting column '+col+'.  Ignoring...');
                    }
                }
            );
            
            // any cells not in the setting must be marked as non-visible
            dojo.forEach(this.cells, function(cell) { 
                if (setting.columns.indexOf(cell.field) == -1) {
                    cell._visible = false;
                    cell._sort = 0;
                }
            });

            this.structure[0].cells[0] = displayCells;
            this.grid.setStructure(this.structure);
            this.grid.update();
        },

        // *only* call this when no usr setting tells us what columns
        // are visible or not.
        pruneInvisibleFields : function() {
            this.structure[0].cells[0] = dojo.filter(
                this.structure[0].cells[0],
                dojo.hitch(this, function(c) {
                    // keep true or undef, lose false
                    return typeof c._visible == "undefined" || c._visible;
                })
            );
        },

        load : function() {
            var _this = this;

            // if load is called before the user has logged in,
            // queue the loading up for after authentication.
            if (!this.authtoken) {
                var _this = this;
                openils.Util.addOnLoad(function() {
                    _this.authtoken = openils.User.authtoken;
                    _this.load();
                }); 
                return;
            }

            if(this.setting) {
                this.loadColsFromSetting(this.setting);
                this._onLoad({sortFields : this.buildSortList()});
                return;
            }

            fieldmapper.standardRequest(
                ['open-ils.actor', 'open-ils.actor.patron.settings.retrieve'],
                {   async: true,
                    params: [this.authtoken, null, this.persistKey],
                    oncomplete: function(r) {
                        var set = openils.Util.readResponse(r);
                        if(set) {
                            _this.loadColsFromSetting(set);
                        } else {
                            _this.grid.setStructure(_this.structure);
                            _this.grid.update();
                        }
                        _this._onLoad({sortFields : _this.buildSortList()});
                    }
                }
            );
        },
    });
}

