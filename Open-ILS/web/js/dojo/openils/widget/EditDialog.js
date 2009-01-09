if(!dojo._hasResource['openils.widget.EditDialog']) {
    dojo.provide('openils.widget.EditDialog');
    dojo.require('openils.widget.AutoWidget');
    dojo.require('fieldmapper.Fieldmapper');
    dojo.require('dijit.Dialog');
    dojo.require('openils.Util');
    dojo.require('openils.User');
    dojo.require('fieldmapper.IDL');


    /**
     * Given a fieldmapper object, this builds a pop-up dialog used for editing the object
     */

    dojo.declare(
        'openils.widget.EditDialog',
        [dijit.Dialog],
        {
            fmClass : '',
            fmObject : null,
            mode : 'update',

            /**
             * Builds a basic table of key / value pairs.  Keys are IDL display labels.
             * Values are dijit's, when values set
             */
            startup : function() {
                this.inherited(arguments);
                this.fmClass = (this.fmObject) ? this.fmObject.classname : this.fmClass;
                fmIDL = fieldmapper.IDL.fmclasses[this.fmClass];

                var table = document.createElement('table');
                var tbody = document.createElement('tbody');
                this.domNode.appendChild(table);
                table.appendChild(tbody);

                this.limitPerms = [];
                if(fmIDL.permacrud && fmIDL.permacrud[this.mode])
                    this.limitPerms = fmIDL.permacrud[this.mode].perms;

                for(var f in fmIDL.fields) {
                    var field = fmIDL.fields[f];
                    if(field.virtual) continue;

                    var row = document.createElement('tr');
                    var nameTd = document.createElement('td');
                    var valTd = document.createElement('td');

                    nameTd.appendChild(document.createTextNode(field.label));
                    row.appendChild(nameTd);
                    row.appendChild(valTd);
                    tbody.appendChild(row);

                    new openils.widget.AutoWidget({
                        idlField : field, 
                        fmObject : this.fmObject,
                        parentNode : valTd,
                        orgLimitPerms : this.limitPerms
                    }).build();
                }

                openils.Util.addCSSClass(table, 'oils-fm-edit-dialog');
            },
        }
    );
}

