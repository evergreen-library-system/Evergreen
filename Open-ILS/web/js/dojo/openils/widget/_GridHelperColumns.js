/* to be inherited by autogrid and similar */
if (!dojo._hasResource["openils.widget._GridHelperColumns"]) {
    dojo._hasResource["openils.widget._GridHelperColumns"] = true;

    dojo.provide("openils.widget._GridHelperColumns");
    dojo.declare(
        "openils.widget._GridHelperColumns", null, {

            "hideSelector": false,
            "selectorWidth": 1.5,
            "hideLineNumber": false,
            "lineNumberWidth": "1.5",

            "getSelectedRows": function() {
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

            "getFirstSelectedRow": function() {
                return this.getSelectedRows()[0];
            },

            "getSelectedItems": function() {
                var items = [];
                var self = this;
                dojo.forEach(this.getSelectedRows(), function(idx) { items.push(self.getItem(idx)); });
                return items;
            },

            "selectRow": function(rowIdx) {
                var inputs = dojo.query('[name=autogrid.selector]', this.domNode);
                for(var i = 0; i < inputs.length; i++) {
                    if(inputs[i].getAttribute('row') == rowIdx) {
                        if(!inputs[i].disabled)
                            inputs[i].checked = true;
                        break;
                    }
                }
            },

            "deSelectRow": function(rowIdx) {
                var inputs = dojo.query('[name=autogrid.selector]', this.domNode);
                for(var i = 0; i < inputs.length; i++) {
                    if(inputs[i].getAttribute('row') == rowIdx) {
                        inputs[i].checked = false;
                        break;
                    }
                }
            },

            "toggleSelectAll": function() {
                var selected = this.getSelectedRows();
                for(var i = 0; i < this.rowCount; i++) {
                    if(selected[0])
                        this.deSelectRow(i);
                    else
                        this.selectRow(i);
                }
            },

            "_formatRowSelectInput": function(rowIdx) {
                if (rowIdx === null || rowIdx === undefined)
                    return "";
                var s = "<input type='checkbox' name='autogrid.selector' row='"
                    + rowIdx + "'";
                if (this.disableSelectorForRow &&
                        this.disableSelectorForRow(rowIdx))
                    s += " disabled='disabled'";
                return s + "/>";
            },

            // style the cells in the line number column
            "onStyleRow": function(row) {
                if (!this.hideLineNumber) {
                    var cellIdx = this.hideSelector ? 0 : 1;
                    dojo.addClass(
                        this.views.views[0].getCellNode(row.index, cellIdx),
                        "autoGridLineNumber"
                    );
                }
            },

            /* Don't allow sorting on the selector column */
            "canSort": function(rowIdx) {
                if (rowIdx == 1 && !this.hideSelector)
                    return false;
                if (this.hideSelector && rowIdx == 1 && !this.hideLineNumber)
                    return false;
                if (!this.hideSelector && rowIdx == 2 && !this.hideLineNumber)
                    return false;
                return true;
            },

            "_startupGridHelperColumns": function() {
                if (!this.hideLineNumber) {
                    this.structure[0].cells[0].unshift({
                        "field": "+lineno",
                        "get": function(rowIdx, item) {
                            if (item) return 1 + rowIdx;
                        },
                        "width": this.lineNumberWidth,
                        "name": "#",
                        "nonSelectable": false
                    });
                }
                if (!this.hideSelector) {
                    this.structure[0].cells[0].unshift({
                        "field": "+selector",
                        "formatter": dojo.hitch(
                            this, function(rowIdx) {
                                return this._formatRowSelectInput(rowIdx);
                            }
                        ),
                        "get": function(rowIdx, item) {
                            if (item) return rowIdx;
                        },
                        "width": this.selectorWidth,
                        "name": "&#x2713",
                        "nonSelectable": true
                    });
                    dojo.connect(
                        this, "onHeaderCellClick", function(e) {
                            if (e.cell.index == 0)
                                this.toggleSelectAll();
                        }
                    );
                }
            }
        }
    );
}
