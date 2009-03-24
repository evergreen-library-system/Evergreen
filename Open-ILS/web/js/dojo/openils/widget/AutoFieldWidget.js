if(!dojo._hasResource['openils.widget.AutoFieldWidget']) {
    dojo.provide('openils.widget.AutoFieldWidget');
    dojo.require('openils.Util');
    dojo.require('openils.User');
    dojo.require('fieldmapper.IDL');

    dojo.declare('openils.widget.AutoFieldWidget', null, {

        async : false,
        cache : {},

        /**
         * args:
         *  idlField -- Field description object from fieldmapper.IDL.fmclasses
         *  fmObject -- If available, the object being edited.  This will be used 
         *      to set the value of the widget.
         *  fmClass -- Class name (not required if idlField or fmObject is set)
         *  fmField -- Field name (not required if idlField)
         *  parentNode -- If defined, the widget will be appended to this DOM node
         *  dijitArgs -- Optional parameters object, passed directly to the dojo widget
         *  orgLimitPerms -- If this field defines a set of org units and an orgLimitPerms 
         *      is defined, the code will limit the org units in the set to those
         *      allowed by the permission
         */
        constructor : function(args) {
            for(var k in args)
                this[k] = args[k];

            // find the field description in the IDL if not provided
            if(this.fmObject) 
                this.fmClass = this.fmObject.classname;
            this.fmIDL = fieldmapper.IDL.fmclasses[this.fmClass];

            if(!this.idlField) {
                this.fmIDL = fieldmapper.IDL.fmclasses[this.fmClass];
                var fields = this.fmIDL.fields;
                for(var f in fields) 
                    if(fields[f].name == this.fmField)
                        this.idlField = fields[f];
            }
        },

        /**
         * Turn the widget-stored value into a value oils understands
         */
        getFormattedValue : function() {
            var value = this.baseWidgetValue();
            switch(this.idlField.datatype) {
                case 'bool':
                    return (value) ? 't' : 'f'
                case 'timestamp':
                    return dojo.date.stamp.toISOString(value);
                case 'int':
                case 'float':
                    if(isNaN(value)) value = 0;
                default:
                    return (value === '') ? null : value;
            }
        },

        baseWidgetValue : function(value) {
            var attr = (this.readOnly) ? 'content' : 'value';
            if(arguments.length) this.widget.attr(attr, value);
            return this.widget.attr(attr);
        },
        
        /**
         * Turn the widget-stored value into something visually suitable
         */
        getDisplayString : function() {
            var value = this.widgetValue;
            switch(this.idlField.datatype) {
                case 'bool':
                    return (value) ? 'True' : 'False'; // XXX i18n!
                case 'timestamp':
                    dojo.require('dojo.date.locale');
                    dojo.require('dojo.date.stamp');
                    var date = dojo.date.stamp.fromISOString(value);
                    return dojo.date.locale.format(date, {formatLength:'short'});
                case 'org_unit':
                    if(value === null || value === undefined) return '';
                    return fieldmapper.aou.findOrgUnit(value).shortname();
                case 'int':
                case 'float':
                    if(isNaN(value)) value = 0;
                default:
                    if(value === undefined || value === null)
                        value = '';
                    return value+'';
            }
        },

        build : function(onload) {

            if(this.widget) {
                // core widget provided for us, attach and move on
                if(this.parentNode) // may already be in the "right" place
                    this.parentNode.appendChild(this.widget.domNode);
                return;
            }

            this.onload = onload;
            if(this.widgetValue == null)
                this.widgetValue = (this.fmObject) ? this.fmObject[this.idlField.name]() : null;

            if(this.readOnly) {
                dojo.require('dijit.layout.ContentPane');
                this.widget = new dijit.layout.ContentPane(this.dijitArgs, this.parentNode);

            } else if(this.widgetClass) {
                dojo.require(this.widgetClass);
                eval('this.widget = new ' + this.widgetClass + '(this.dijitArgs, this.parentNode);');

            } else {

                switch(this.idlField.datatype) {
                    
                    case 'id':
                        dojo.require('dijit.form.TextBox');
                        this.widget = new dijit.form.TextBox(this.dijitArgs, this.parentNode);
                        this.widget.attr('disabled', true); // never allow editing of IDs
                        break;

                    case 'org_unit':
                        this._buildOrgSelector();
                        break;

                    case 'money':
                        dojo.require('dijit.form.CurrencyTextBox');
                        this.widget = new dijit.form.CurrencyTextBox(this.dijitArgs, this.parentNode);
                        break;

                    case 'int':
                        dojo.require('dijit.form.NumberTextBox');
                        this.dijitArgs = dojo.mixin(this.dijitArgs || {}, {constraints:{places:0}});
                        this.widget = new dijit.form.NumberTextBox(this.dijitArgs, this.parentNode);
                        break;

                    case 'float':
                        dojo.require('dijit.form.NumberTextBox');
                        this.widget = new dijit.form.NumberTextBox(this.dijitArgs, this.parentNode);
                        break;

                    case 'timestamp':
                        dojo.require('dijit.form.DateTextBox');
                        dojo.require('dojo.date.stamp');
                        this.widget = new dijit.form.DateTextBox(this.dijitArgs, this.parentNode);
                        if(this.widgetValue != null) 
                            this.widgetValue = dojo.date.stamp.fromISOString(this.widgetValue);
                        break;

                    case 'bool':
                        dojo.require('dijit.form.CheckBox');
                        this.widget = new dijit.form.CheckBox(this.dijitArgs, this.parentNode);
                        this.widgetValue = openils.Util.isTrue(this.widgetValue);
                        break;

                    case 'link':
                        if(this._buildLinkSelector()) break;

                    default:
                        dojo.require('dijit.form.TextBox');
                        this.widget = new dijit.form.TextBox(this.dijitArgs, this.parentNode);
                }
            }

            if(!this.async) this._widgetLoaded();
            return this.widget;
        },

        _buildLinkSelector : function() {

            /* verify we can and should grab the related class */
            var linkClass = this.idlField['class'];
            if(this.idlField.reltype != 'has_a')  return false;
            if(!fieldmapper.IDL.fmclasses[linkClass].permacrud) return false;
            if(!fieldmapper.IDL.fmclasses[linkClass].permacrud.retrieve) return false;

            dojo.require('openils.PermaCrud');
            dojo.require('dojo.data.ItemFileReadStore');
            dojo.require('dijit.form.FilteringSelect');

            var self = this;
            var vfield;
            var rclassIdl = fieldmapper.IDL.fmclasses[linkClass];

            if(linkClass == 'pgt')
                return self._buildPermGrpSelector();

            this.async = true;
            this.widget = new dijit.form.FilteringSelect(this.dijitArgs, this.parentNode);

            for(var f in rclassIdl.fields) {
                if(self.idlField.key == rclassIdl.fields[f].name) {
                    vfield = rclassIdl.fields[f];
                    break;
                }
            }

            if(!vfield) 
                throw new Error("'" + linkClass + "' has no '" + self.idlField.key + "' field!");

            this.widget.searchAttr = this.widget.labelAttr = vfield.selector || vfield.name;
            this.widget.valueAttr = vfield.name;

            var oncomplete = function(list) {
                if(list) {
                    self.widget.store = 
                        new dojo.data.ItemFileReadStore({data:fieldmapper[linkClass].toStoreData(list)});
                    self.cache[linkClass] = list;
                }
                self.widget.startup();
                self._widgetLoaded();
            };

            if(this.cache[linkClass]) {
                oncomplete(this.cache[linkClass]);

            } else {
                new openils.PermaCrud().retrieveAll(linkClass, {   
                    async : true,
                    oncomplete : function(r) {
                        var list = openils.Util.readResponse(r, false, true);
                        oncomplete(list);
                    }
                });
            }

            return true;
        },

        /**
         * For widgets that run asynchronously, provide a callback for finishing up
         */
        _widgetLoaded : function(value) {
            if(this.readOnly) {
                this.baseWidgetValue(this.getDisplayString());
            } else {
                this.baseWidgetValue(this.widgetValue);
                if(this.idlField.name == this.fmIDL.pkey && this.fmIDL.pkey_sequence)
                    this.widget.attr('disabled', true); 
            }
            if(this.onload)
                this.onload(this.widget, self);
        },

        _buildOrgSelector : function() {
            dojo.require('fieldmapper.OrgUtils');
            dojo.require('openils.widget.FilteringTreeSelect');
            this.widget = new openils.widget.FilteringTreeSelect(this.dijitArgs, this.parentNode);
            this.widget.searchAttr = 'shortname';
            this.widget.labelAttr = 'shortname';
            this.widget.parentField = 'parent_ou';
            var user = new openils.User();
            if(this.widgetValue == null) 
                this.widgetValue = user.user.ws_ou();
            
            // if we have a limit perm, find the relevent orgs (async)
            if(this.orgLimitPerms && this.orgLimitPerms.length > 0) {
                this.async = true;
                var self = this;
                user.getPermOrgList(this.orgLimitPerms, 
                    function(orgList) {
                        self.widget.tree = orgList;
                        self.widget.startup();
                        self._widgetLoaded();
                    }
                );

            } else {
                this.widget.tree = fieldmapper.aou.globalOrgTree;
                this.widget.startup();
            }
        },

        _buildPermGrpSelector : function() {
            dojo.require('openils.widget.FilteringTreeSelect');
            this.widget = new openils.widget.FilteringTreeSelect(this.dijitArgs, this.parentNode);
            this.widget.searchAttr = 'name';

            if(this.cache.permGrpTree) {
                this.widget.tree = this.cache.permGrpTree;
                this.widget.startup();
                return;
            } 

            var self = this;
            this.async = true;
            new openils.PermaCrud().retrieveAll('pgt', {
                async : true,
                oncomplete : function(r) {
                    var list = openils.Util.readResponse(r, false, true);
                    if(!list) return;
                    var map = {};
                    var root = null;
                    for(var l in list)
                        map[list[l].id()] = list[l];
                    for(var l in list) {
                        var node = list[l];
                        var pnode = map[node.parent()];
                        if(!pnode) {root = node; continue;}
                        if(!pnode.children()) pnode.children([]);
                        pnode.children().push(node);
                    }
                    self.widget.tree = self.cache.permGrpTree = root;
                    self.widget.startup();
                    self._widgetLoaded();
                }
            });

            return true;
        }
    });
}

