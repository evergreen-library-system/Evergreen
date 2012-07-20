if(!dojo._hasResource['openils.widget.EditPane']) {
    dojo.provide('openils.widget.EditPane');
    dojo.require('openils.widget.AutoWidget');
    dojo.require('openils.widget.AutoFieldWidget');
    dojo.require('fieldmapper.Fieldmapper');
    dojo.require('dijit.layout.ContentPane');
    dojo.require('openils.Util');
    dojo.require('openils.PermaCrud');
    dojo.require('dijit.form.Button');

    dojo.declare(
        'openils.widget.EditPane',
        [dijit.layout.ContentPane, openils.widget.AutoWidget],
        {
            mode : 'update',
            onPostSubmit : null, // apply callback
            onCancel : null, // cancel callback
            hideActionButtons : false,
            fieldDocs : null,
            existingTable : null,
            suppressFields : null,
            requiredFields : null,
            paneStackCount : 1, // how many fields to add to each row, for compressing display

            constructor : function(args) {
                this.fieldList = [];
                for(var k in args)
                    this[k] = args[k];
            },

            /**
             * Builds a basic table of key / value pairs.  Keys are IDL display labels.
             * Values are dijit's, when values set
             */
            startup : function() {
                this.inherited(arguments);
                this.initAutoEnv();
                if(this.readOnly)
                    this.hideSaveButton = true;

                // grab any field-level docs
                /*
                var pcrud = new openils.PermaCrud();
                this.fieldDocs = pcrud.search('fdoc', {fm_class:this.fmClass});
                */

                var table = this.existingTable;
                if(!table) {
                    var table = this.table = document.createElement('table');
                    this.domNode.appendChild(table);
                }
                var tbody = document.createElement('tbody');
                table.appendChild(tbody);

                this.limitPerms = [];
                if(this.fmIDL.permacrud && this.fmIDL.permacrud[this.mode])
                    this.limitPerms = this.fmIDL.permacrud[this.mode].perms;

                if(!this.overrideWidgets)
                    this.overrideWidgets = {};

                if(!this.overrideWidgetClass)
                    this.overrideWidgetClass = {};

                if(!this.overrideWidgetArgs)
                    this.overrideWidgetArgs = {};

                var idx = 0;
                var currentRow;
                for(var f in this.sortedFieldList) {
                    var field = this.sortedFieldList[f];
                    if(!field || field.virtual || field.nonIdl) continue;

                    if(this.suppressFields && this.suppressFields.indexOf(field.name) > -1)
                        continue;

                    if(field.name == this.fmIDL.pkey && this.mode == 'create' && this.fmIDL.pkey_sequence)
                        continue; /* don't show auto-generated fields on create */

                    if(!this.overrideWidgetArgs[field.name])
                        this.overrideWidgetArgs[field.name] = {};

                    if(this.overrideWidgetArgs[field.name].hrbefore && this.paneStackCount <= 1) {
                        var hrTr = document.createElement('tr');
                        var hrTd = document.createElement('td');
                        var hr = document.createElement('hr');
                        hrTd.colSpan = 2;
                        dojo.addClass(hrTd, 'openils-widget-editpane-hr-cell');
                        hrTd.appendChild(hr);
                        hrTr.appendChild(hrTd);
                        tbody.appendChild(hrTr);
                    }

                    if((idx++ % this.paneStackCount) == 0 || !currentRow) {
                        // time to start a new row
                        currentRow = document.createElement('tr');
                        tbody.appendChild(currentRow);
                    }

                    //var docTd = document.createElement('td');
                    var nameTd = document.createElement('td');
                    var valTd = document.createElement('td');
                    var valSpan = document.createElement('span');
                    valTd.appendChild(valSpan);
                    dojo.addClass(nameTd, 'openils-widget-editpane-name-cell');
                    dojo.addClass(valTd, 'openils-widget-editpane-value-cell');

                    /*
                    if(this.fieldDocs[field]) {
                        var helpLink = dojo.create('a');
                        var helpImg = dojo.create('img', {src:'/opac/images/advancedsearch-icon.png'}); // TODO Config
                        helpLink.appendChild(helpImg);
                        docTd.appendChild(helpLink);
                    }
                    */

                    nameTd.appendChild(document.createTextNode(field.label));
                    currentRow.setAttribute('fmfield', field.name);
                    //currentRow.appendChild(docTd);
                    currentRow.appendChild(nameTd);
                    currentRow.appendChild(valTd);
                    //dojo.addClass(docTd, 'oils-fm-edit-pane-help');

                    var args = dojo.mixin(
                        {   // defaults
                            idlField : field, 
                            fmObject : this.fmObject,
                            fmClass : this.fmClass,
                            parentNode : valSpan,
                            orgLimitPerms : this.limitPerms,
                            readOnly : this.readOnly,
                            widget : this.overrideWidgets[field.name],
                            widgetClass : this.overrideWidgetClass[field.name],
                            disableWidgetTest : this.disableWidgetTest
                        },
                        this.overrideWidgetArgs[field.name] // per-field overrides
                    );

                    if (this.overrideWidgets[field.name]) {
                        if (this.overrideWidgets[field.name].shove) {
                            args.shove = dojo.mixin(
                                {"mode": this.mode},
                                this.overrideWidgets[field.name].shove
                            );
                        }
                    }

                    if(args.readOnly) {
                        dojo.addClass(nameTd, 'openils-widget-editpane-ro-name-cell');
                        dojo.addClass(valTd, 'openils-widget-editpane-ro-value-cell');
                    }

                    if(this.requiredFields && this.requiredFields.indexOf(field.name) >= 0) {
                        if(!args.dijitArgs) args.dijitArgs = {};
                        args.dijitArgs.required = true;
                    }

                    var widget = new openils.widget.AutoFieldWidget(args);

                    widget.build();
                    this.fieldList.push({name:field.name, widget:widget});
                }
                if(!this.hideActionButtons)
                    this.buildActionButtons(tbody);

                openils.Util.addCSSClass(table, 'oils-fm-edit-pane');
            },

            applySaveOnEnter : function(widget) {
                var self = this;
                dojo.connect(this, 'onKeyDown',
                    function(e) {
                        if(e.keyCode == dojo.keys.ENTER) 
                            self.performAutoEditAction();
                    }
                );
            },

            buildActionButtons : function(tbody) {
                var row = document.createElement('tr');
                var cancelTd = document.createElement('td');
                var applyTd = document.createElement('td');
                var cancelSpan = document.createElement('span');
                var applySpan = document.createElement('span');
                row.appendChild(cancelTd);
                row.appendChild(applyTd);
                cancelTd.appendChild(cancelSpan);
                applyTd.appendChild(applySpan);
                tbody.appendChild(row);

                var self = this;
                new dijit.form.Button({
                    label:'Cancel', // XXX
                    onClick : this.onCancel
                }, cancelSpan);

                if(this.hideSaveButton) return;

                new dijit.form.Button({
                    label:'Save',  // XXX
                    onClick: function() {self.performAutoEditAction();}
                }, applySpan);
            },

            getFields : function() {
                return this.fieldList.map(function(a) { return a.name });
            },

            // Apply a function for the name and formatted value of each field
            // in this edit pane.  If any required value is null, then return
            // an error object.
            mapValues: function (fn) {
                var e = 0, msg = this.fmIDL.label + ' ';
                dojo.forEach(this.fieldList, function (f) {
                    var v, w = f.widget;
                    if ((v = w.getFormattedValue()) === null && w.isRequired()) { e++; }
                    fn(f.name, v);
                });
                if (e > 0) {
                    msg += 'edit pane has ' + e + ' required field(s) that contain no value(s)';
                    return new Error(msg);
                }
            },

            getFieldValue : function(field, checkRequired) {
                for(var i in this.fieldList) {
                    if(field == this.fieldList[i].name) {
                        var val = this.fieldList[i].widget.getFormattedValue();
                        if (checkRequired &&
                            val == null && /* XXX stricter check needed? */
                            this.fieldList[i].widget.isRequired()) {
                            throw new Error("req");
                        }
                        return val;

                    }
                }
            },

            setFieldValue : function(field, val) {
                for(var i in this.fieldList) {
                    if(field == this.fieldList[i].name) {
                        this.fieldList[i].widget.widget.attr('value', val);
                    }
                }
            },


            performAutoEditAction : function() {
                var self = this;
                self.performEditAction({
                    oncomplete:function(req, cudResults) {
                        if(self.onPostSubmit)
                            self.onPostSubmit(req, cudResults);
                    }
                });
            },

            performEditAction : function(opts) {
                var self = this;
                var fields = this.getFields();
                if(this.mode == 'create')
                    this.fmObject = new fieldmapper[this.fmClass]();
                try {
                    for(var idx in fields) {
                        this.fmObject[fields[idx]](
                            this.getFieldValue(fields[idx], true)
                        );
                    }
                } catch (E) {
                    if (E.message == "req") /* req'd field set to null. bail. */
                        return;
                    else /* something else went wrong? */
                        throw E;
                }
                if(this.mode == 'create' && this.fmIDL.pkey_sequence)
                    this.fmObject[this.fmIDL.pkey](null);
                if (typeof(this.onSubmit) == "function") {
                    this.onSubmit(this.fmObject, opts, self);
                } else {
                    (new openils.PermaCrud())[this.mode](this.fmObject, opts);
                }
            }
        }
    );
}

