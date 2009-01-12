if(!dojo._hasResource['openils.widget.EditPane']) {
    dojo.provide('openils.widget.EditPane');
    dojo.require('openils.widget.AutoWidget');
    dojo.require('fieldmapper.Fieldmapper');
    dojo.require('dijit.layout.ContentPane');
    dojo.require('openils.Util');
    dojo.require('openils.User');
    dojo.require('fieldmapper.IDL');

    dojo.declare(
        'openils.widget.EditPane',
        [dijit.layout.ContentPane],
        {
            fmClass : '',
            fmObject : null,
            mode : 'update',
            fieldOrder : null, // ordered list of field names, optional.
            fieldList : [], // holds the field name + associated widget
            sortedFieldList : [], // holds the sorted IDL defs for our fields

            /**
             * Builds a basic table of key / value pairs.  Keys are IDL display labels.
             * Values are dijit's, when values set
             */
            startup : function() {
                this.inherited(arguments);
                this.fmClass = (this.fmObject) ? this.fmObject.classname : this.fmClass;
                this.fmIDL = fieldmapper.IDL.fmclasses[this.fmClass];

                var table = document.createElement('table');
                var tbody = document.createElement('tbody');
                this.domNode.appendChild(table);
                table.appendChild(tbody);

                this.limitPerms = [];
                if(this.fmIDL.permacrud && this.fmIDL.permacrud[this.mode])
                    this.limitPerms = this.fmIDL.permacrud[this.mode].perms;

                this._buildSortedFieldList()

                for(var f in this.sortedFieldList) {
                    var field = this.sortedFieldList[f];
                    if(!field || field.virtual) continue;

                    var row = document.createElement('tr');
                    var nameTd = document.createElement('td');
                    var valTd = document.createElement('td');

                    nameTd.appendChild(document.createTextNode(field.label));
                    row.appendChild(nameTd);
                    row.appendChild(valTd);
                    tbody.appendChild(row);

                    var widget = new openils.widget.AutoWidget({
                        idlField : field, 
                        fmObject : this.fmObject,
                        parentNode : valTd,
                        orgLimitPerms : this.limitPerms
                    });
                    widget.build();
                    this.fieldList.push({name:field.name, widget:widget});
                }

                openils.Util.addCSSClass(table, 'oils-fm-edit-dialog');
            },

            getFields : function() {
                return this.fieldList.map(function(a) { return a.name });
            },

            getFieldValue : function(field) {
                for(var i in this.fieldList) {
                    if(field == this.fieldList[i].name)
                        return this.fieldList[i].widget.getFormattedValue();
                }
            },

            _buildSortedFieldList : function() {
                this.sortedFieldList = [];

                if(this.fieldOrder) {

                    for(var idx in this.fieldOrder) {
                        var name = this.fieldOrder[idx];
                        for(var idx2 in this.fmIDL.fields) {
                            if(this.fmIDL.fields[idx2].name == name) {
                                this.sortedFieldList.push(this.fmIDL.fields[idx2]);
                                break;
                            }
                        }
                    }
                    
                    // if the user-defined order does not list all fields, 
                    // shove the extras on the end.
                    var anonFields = [];
                    for(var idx in this.fmIDL.fields)  {
                        var name = this.fmIDL.fields[idx].name;
                        if(this.fieldOrder.indexOf(name) < 0) {
                            anonFields.push(this.fmIDL.fields[idx]);
                        }
                    }

                    anonFields = anonFields.sort(
                        function(a, b) {
                            if(a.label > b.label) return 1;
                            if(a.label < b.label) return -1;
                            return 0;
                        }
                    );

                    this.sortedFieldList = this.sortedFieldList.concat(anonFields);

                } else {
                    // no sort order defined, sort all fields on display label

                    for(var f in this.fmIDL.fields) 
                        this.sortedFieldList.push(this.fmIDL.fields[f]);
                    this.sortedFieldList = this.sortedFieldList.sort(
                        // by default, sort on label
                        function(a, b) {
                            if(a.label > b.label) return 1;
                            if(a.label < b.label) return -1;
                            return 0;
                        }
                    );
                } 
            }
        }
    );
}

