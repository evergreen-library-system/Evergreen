if(!dojo._hasResource['openils.widget.AutoFieldWidget']) {
    dojo.provide('openils.widget.AutoFieldWidget');
    dojo.require('openils.Util');
    dojo.require('openils.User');
    dojo.require('fieldmapper.IDL');

    dojo.declare('openils.widget.AutoFieldWidget', null, {

        async : false,

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
            if(!this.idlField) {
                if(this.fmObject)
                    this.fmClass = this.fmObject.classname;
                var fields = fieldmapper.IDL.fmclasses[this.fmClass].fields;
                for(var f in fields) 
                    if(fields[f].name == this.fmField)
                        this.idlField = fields[f];
            }
        },

        /**
         * Turn the value from the dojo widget into a value oils understands
         */
        getFormattedValue : function() {
            var value = this.widget.attr('value');
            switch(this.idlField.datatype) {
                case 'bool':
                    return (value) ? 't' : 'f'
                case 'timestamp':
                    return dojo.date.stamp.toISOString(value);
                default:
                    return value;
            }
        },
        
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
                    return fieldmapper.aou.findOrgUnit(value).shortname();
                default:
                    return value;
            }
        },

        build : function(onload) {
            this.onload = onload;
            if(this.widgetValue == null)
                this.widgetValue = (this.fmObject) ? this.fmObject[this.idlField.name]() : null;

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

            if(!this.async) this._widgetLoaded();
            return this.widget;
        },

        _buildLinkSelector : function() {
            if(this.idlField.reltype != 'has_a') return false;

            dojo.require('openils.PermaCrud');
            dojo.require('dojo.data.ItemFileReadStore');
            dojo.require('dijit.form.FilteringSelect');

            var self = this;
            this.async = true;
            var linkClass = this.idlField['class'];
            this.widget = new dijit.form.FilteringSelect(this.dijitArgs, this.parentNode);
            var rclassIdl = fieldmapper.IDL.fmclasses[linkClass];
            var vfield;

            for(var f in rclassIdl.fields) {
                if(self.idlField.key == rclassIdl.fields[f].name) {
                    vfield = rclassIdl.fields[f];
                    break;
                }
            }

            this.widget.searchAttr = this.widget.labelAttr = vfield.selector || vfield.name;
            this.widget.valueAttr = vfield.name;

            new openils.PermaCrud().retrieveAll(linkClass, {   
                async : true,
                oncomplete : function(r) {
                    var list = openils.Util.readResponse(r, false, true);
                    if(list) {
                        self.widget.store = 
                            new dojo.data.ItemFileReadStore({data:fieldmapper[linkClass].toStoreData(list)});
                    }
                    self.widget.startup();
                    self._widgetLoaded();
                }
            });

            return true;
        },

        /**
         * For widgets that run asynchronously, provide a callback for finishing up
         */
        _widgetLoaded : function(value) {
            if(this.widgetValue != null) 
                this.widget.attr('value', this.widgetValue);
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
            
            // if we have a limit perm, find the relevent orgs (async)
            if(this.orgLimitPerms && this.orgLimitPerms.length > 0) {
                this.async = true;
                var user = new openils.User();
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
        }
    });
}

