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
    dojo.require('openils.User');
    dojo.require('openils.Event');
    dojo.require('openils.Util');
    dojo.require('fieldmapper.Fieldmapper');


    dojo.declare('openils.widget.GridColumnPicker', null, {

        USER_PERSIST_SETTING : 'ui.grid_columns',

        constructor : function (authtoken, persistPrefix, grid, structure) {
            this.dialog = this.buildDialog();
            this.grid = grid;
            this.structure = structure;
            if(!structure) 
                this.structure = this.grid.attr('structure');
            this.dialogTable = this.dialog.domNode.getElementsByTagName('tbody')[0];
            this.baseCellList = this.structure[0].cells[0].slice();
            this.build();
            this.authtoken = authtoken;
            this.savedColums = null;
            this.persistPrefix = persistPrefix;
            this.setting = null;

            var self = this;
            this.grid.onHeaderContextMenu = function(e) { 
                self.dialog.show(); 
                dojo.stopEvent(e);
            };
        },

        buildDialog : function() {
            var self = this;
            
            // TODO i18n

            var dialog = new dijit.Dialog({title : 'Column Picker'});
            var table = dojo.create('table', {'class':'oils-generic-table', innerHTML : 
                "<thead><tr><th width='33%'>Column</th><th width='33%'>Display</th><th width='33%'>Auto Width</th></tr></thead>" +
                "<tbody><tr><td><div name='cancel_button'/></td><td><div name='save_button'/></td></tr></tbody></table>" });

            dialog.domNode.appendChild(table);

            var button = new dijit.form.Button({label:'Save'}, dojo.query('[name=save_button]', table)[0]);
            button.onClick = function() { dialog.hide(); self.update(true); };

            button = new dijit.form.Button({label:'Cancel'}, dojo.query('[name=cancel_button]', table)[0]);
            button.onClick = function() { dialog.hide(); };

            return dialog;
        },

        // builds the column-picker dialog table
        build : function() {
            var  cells = this._selectableCellList();
            var str = '';
            var rows = dojo.query('tr', this.dialogTable);

            for(var i = 0; i < rows.length; i++) {
                if(rows[i].getAttribute('picker'))
                    this.dialogTable.removeChild(rows[i]);
            }

            rows = dojo.query('tr', this.dialogTable);
            var lastChild = null;
            if(rows.length > 0)
                lastChild = rows[rows.length-1];

            for(var i = 0; i < cells.length; i++) {
                // setting table.innerHTML breaks stuff, so do it the hard way
                var cell = cells[i];
                tr = document.createElement('tr');
                tr.setAttribute('picker', 'picker');
                td1 = document.createElement('td');
                td2 = document.createElement('td');
                td3 = document.createElement('td');

                ipt = document.createElement('input');
                ipt.setAttribute('type', 'checkbox');
                ipt.setAttribute('checked', 'checked');
                ipt.setAttribute('ident', cell.field+''+cell.name);
                ipt.setAttribute('name', 'selector');

                ipt2 = document.createElement('input');
                ipt2.setAttribute('type', 'checkbox');
                ipt2.setAttribute('ident', cell.field+''+cell.name);
                ipt2.setAttribute('name', 'width');

                if(this.setting) {
                    // set the UI based on the loaded settings
                    if(this._arrayHas(this.setting.columns, cell.field)) {
                        if(this._arrayHas(this.setting.auto, cell.field))
                            ipt2.setAttribute('checked', 'checked');
                    } else {
                        ipt.removeAttribute('checked');
                    }
                }

                td1.appendChild(document.createTextNode(cell.name));
                td2.appendChild(ipt);
                td3.appendChild(ipt2);
                tr.appendChild(td1);
                tr.appendChild(td2);
                tr.appendChild(td3);
                if(lastChild)
                    this.dialogTable.insertBefore(tr, lastChild);
                else
                    this.dialogTable.appendChild(tr);
            }
        },

        // update the grid based on the items selected in the picker dialog
        update : function(persist) {
            var newCellList = [];
            var rows = dojo.query('[picker=picker]', this.dialogTable);

            for(var j = 0; j < this.baseCellList.length; j++) {
                var cell = this.baseCellList[j];
                if(cell.selectableColumn) {
                    for(var i = 0; i < rows.length; i++) {
                        var row = rows[i];
                        var selector = dojo.query('[name=selector]', row)[0];
                        var width = dojo.query('[name=width]', row)[0];
                        if(selector.checked && selector.getAttribute('ident') == cell.field+''+cell.name) {
                            if(width.checked)
                                cell.width = 'auto';
                            else delete cell.width;
                            newCellList.push(cell);
                        }
                    }
                } else { // if it's not selectable, always show it
                    newCellList.push(cell); 
                }
            }

            this.structure[0].cells[0] = newCellList;
            this.grid.setStructure(this.structure);
            this.grid.update();

            if(persist) this.persist();
        },

        _selectableCellList : function() {
            var cellList = this.structure[0].cells[0];
            var cells = [];
            for(var i = 0; i < cellList.length; i++) {
                var cell = cellList[i];
                if(!cell.nonSelectable) cell.selectableColumn = true;
                if(cell.selectableColumn) 
                    cells.push({name:cell.name, field:cell.field}); 
            }
            return cells;
        },

        // save me as a user setting
        persist : function() {
            var cells = this.structure[0].cells[0];
            var list = [];
            var autos = [];
            for(var i = 0; i < cells.length; i++) {
                var cell = cells[i];
                if(cell.selectableColumn) {
                    list.push(cell.field);
                    if(cell.width == 'auto')
                        autos.push(cell.field);
                }
            }
            var setting = {};
            setting[this.USER_PERSIST_SETTING+'.'+this.persistPrefix] = {'columns':list, 'auto':autos};
            fieldmapper.standardRequest(
                ['open-ils.actor', 'open-ils.actor.patron.settings.update'],
                {   async: true,
                    params: [this.authtoken, null, setting],
                    oncomplete: function(r) {
                        var stat = r.recv().content();
                        if(e = openils.Event.parse(stat))
                            return alert(e);
                    }
                }
            );
        }, 

        _arrayHas : function(arr, val) {
            for(var i = 0; arr && i < arr.length; i++) {
                if(arr[i] == val)
                    return true;
            }
            return false;
        },

        _loadColsFromSetting : function(setting) {
            this.setting = setting;
            var newCellList = [];
            for(var j = 0; j < this.baseCellList.length; j++) {
                var cell = this.baseCellList[j];
                if(cell.selectableColumn) {
                    if(this._arrayHas(setting.columns, cell.field)) {
                        newCellList.push(cell);
                        if(this._arrayHas(setting.auto, cell.field))
                            cell.width = 'auto';
                        else delete cell.width;
                    }
                }  else { // if it's not selectable, always show it
                    newCellList.push(cell); 
                }
            }

            this.build();
            this.structure[0].cells[0] = newCellList;
            this.grid.setStructure(this.structure);
            this.grid.update();
        },

        load : function() {
            if(this.setting)
                return this._loadColsFromSetting(this.setting);
            var picker = this;
            fieldmapper.standardRequest(
                ['open-ils.actor', 'open-ils.actor.patron.settings.retrieve'],
                {   async: true,
                    params: [this.authtoken, null, this.USER_PERSIST_SETTING+'.'+this.persistPrefix],
                    oncomplete: function(r) {
                        var set = openils.Util.readResponse(r);
                        if(set) {
                            picker._loadColsFromSetting(set);
                        } else {
                            picker.build();
                            picker.grid.setStructure(picker.structure);
                            picker.grid.update();
                        }
                    }
                }
            );
        },
    });
}

