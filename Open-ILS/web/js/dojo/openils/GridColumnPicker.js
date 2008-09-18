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

if(!dojo._hasResource["openils.GridColumnPicker"]) {
    dojo._hasResource["openils.GridColumnPicker"] = true;
    dojo.provide('openils.GridColumnPicker');
    dojo.declare('openils.GridColumnPicker', null, {

        constructor : function (dialog, grid) {
            this.dialog = dialog;
            this.grid = grid;
            this.structure = grid.structure;
            this.dialogTable = dialog.domNode.getElementsByTagName('tbody')[0];
            this.baseCellList = this.structure[0].cells[0].slice();
            this.build();
            this.grid.model.fields.get(0).sort = false;
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
                tr = document.createElement('tr');
                tr.setAttribute('picker', 'picker');
                td1 = document.createElement('td');
                td2 = document.createElement('td');
                td3 = document.createElement('td');

                ipt = document.createElement('input');
                ipt.setAttribute('type', 'checkbox');
                ipt.setAttribute('checked', 'checked');
                ipt.setAttribute('ident', cells[i].field+''+cells[i].name);
                ipt.setAttribute('name', 'selector');

                ipt2 = document.createElement('input');
                ipt2.setAttribute('type', 'checkbox');
                ipt2.setAttribute('ident', cells[i].field+''+cells[i].name);
                ipt2.setAttribute('name', 'width');

                td1.appendChild(document.createTextNode(cells[i].name));
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
        update : function() {
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
        },

        _selectableCellList : function() {
            var cellList = this.structure[0].cells[0];
            var cells = [];
            for(var i = 0; i < cellList.length; i++) {
                var cell = cellList[i];
                if(cell.selectableColumn) 
                    cells.push({name:cell.name, field:cell.field}); 
            }
            return cells;
        },

        // save me as a user setting
        persist : function() {
        }
    });
}

