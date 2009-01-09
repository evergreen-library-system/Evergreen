if(!dojo._hasResource['openils.widget.AutoWidget']) {
    dojo.provide('openils.widget.AutoWidget');
    dojo.require('openils.Util');
    dojo.require('openils.User');
    dojo.require('fieldmapper.IDL');

    dojo.declare('openils.widget.AutoWidget', null, {

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
                var fields = fieldmapper.IDL.fmclasses[this.fmClass][fields];
                for(var f in fields) 
                    if(fields[f].name == this.fmField)
                        this.idlField = fields[f];
            }
        },

        build : function(onload) {
            this.onload = onload;
            this.widgetValue = (this.fmObject) ? this.fmObject[this.idlField.name]() : null;

            switch(this.idlField.datatype) {

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

                default:
                    dojo.require('dijit.form.TextBox');
                    this.widget = new dijit.form.TextBox(this.dijitArgs, this.parentNode);
            }

            if(!this.async) this._widgetLoaded();
            return this.widget;
        },

        /**
         * For widgets that run asynchronously, provide a callback for finishing up
         */
        _widgetLoaded : function(value) {
            if(this.fmObject) 
                this.widget.attr('value', this.widgetValue);
            if(this.onload)
                this.onload(this.widget, self);
        },

        _buildOrgSelector : function() {
            dojo.require('fieldmapper.OrgUtils');
            dojo.require('openils.widget.FilteringTreeSelect');
            this.widget = new openils.widget.FilteringTreeSelect(this.dijitArgs, this.parentNode);
            this.widget.searchAttr = 'shortname';

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
            }
        }
    });
}

