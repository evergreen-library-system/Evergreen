if(!dojo._hasResource['openils.widget.AutoFieldWidget']) {
    dojo.provide('openils.widget.AutoFieldWidget');
    dojo.require('openils.Util');
    dojo.require('openils.User');
    dojo.require('fieldmapper.IDL');
    dojo.require('openils.PermaCrud');
	dojo.requireLocalization("openils.widget", "AutoFieldWidget");

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
         *  orgDefaultsToWs -- If this is an org unit field and the widget has no value,
         *      set the value equal to the users's workstation org unit.  Othwerwise, leave it null
         *  selfReference -- The primary purpose of an AutoFieldWidget is to render the value
         *      or widget for a field on an object (that may or may not link to another object).
         *      selfReference allows you to sidestep the indirection and create a selector widget
         *      based purely on an fmClass.  To get a dropdown of all of the 'abc'
         *      objects, pass in {selfReference : true, fmClass : 'abc'}.  
         *  labelFormat -- For widgets that are displayed as remote object filtering selects,
         *      this provides a mechanism for overriding the label format in the filtering select.
         *      It must be an array, whose first value is a format string, compliant with
         *      dojo.string.substitute.  The remaining array items are the arguments to the format
         *      represented as field names on the remote linked object.
         *      E.g.
         *      labelFormat : [ '${0} (${1})', 'obj_field_1', 'obj_field_2' ]
         *      Note: this does not control the final display value.  Only values in the drop-down.
         *      See searchFormat for controlling the display value
         *  searchFormat -- This format controls the structure of the search attribute which
         *      controls the text used during type-ahead searching and the displayed value in 
         *      the filtering select.  See labelFormat for the structure.  
         *  dataLoader : Bypass the default PermaCrud linked data fetcher and use this function instead.
         *      Function arguments are (link class name, search filter, callback)
         *      The fetched objects should be passed to the callback as an array
         *  disableQuery : dojo.data query passed to FilteringTreeSelect-based widgets to disable
         *      (but leave visible) certain options.  
         *  useWriteStore : tells AFW to use a dojo.data.ItemFileWriteStore instead of a ReadStore for
         *      data stores created with dynamic data.  This allows the caller to add/remove items from 
         *      the store.
         */
        constructor : function(args) {
            for(var k in args)
                this[k] = args[k];

            if (!this.dijitArgs) {
                this.dijitArgs = {};
            }
            this.dijitArgs['scrollOnFocus'] = false;


            // find the field description in the IDL if not provided
            if(this.fmObject) 
                this.fmClass = this.fmObject.classname;
            this.fmIDL = fieldmapper.IDL.fmclasses[this.fmClass];

            if(this.fmClass && !this.fmIDL) {
                fieldmapper.IDL.load([this.fmClass]);
                this.fmIDL = fieldmapper.IDL.fmclasses[this.fmClass];
            }

            this.suppressLinkedFields = args.suppressLinkedFields || [];

            if(this.selfReference) {
                this.fmField = fieldmapper.IDL.fmclasses[this.fmClass].pkey;
                
                // create a mock-up of the idlField object.  
                this.idlField = {
                    datatype : 'link',
                    'class' : this.fmClass,
                    reltype : 'has_a',
                    key : this.fmField,
                    name : this.fmField
                };

            } else {

                if(!this.idlField) {
                    this.fmIDL = fieldmapper.IDL.fmclasses[this.fmClass];
                    var fields = this.fmIDL.fields;
                    for(var f in fields) 
                        if(fields[f].name == this.fmField)
                            this.idlField = fields[f];
                }
            }

            if(!this.idlField) 
                throw new Error("AutoFieldWidget could not determine which " +
                    "field to render.  We need more information. fmClass=" + 
                    this.fmClass + ' fmField=' + this.fmField + ' fmObject=' + js2JSON(this.fmObject));

            this.auth = openils.User.authtoken;
            this.cache = openils.widget.AutoFieldWidget.cache;
            this.cache[this.auth] = this.cache[this.auth] || {};
            this.cache[this.auth].single = this.cache[this.auth].single || {};
            this.cache[this.auth].list = this.cache[this.auth].list || {};

            if (this.useWriteStore) {
                dojo.require('dojo.data.ItemFileWriteStore');
                this.storeConstructor = dojo.data.ItemFileWriteStore;
            } else {
                this.storeConstructor = dojo.data.ItemFileReadStore;
            }
        },

        /**
         * Turn the widget-stored value into a value oils understands
         */
        getFormattedValue : function() {
            var value = this.baseWidgetValue();
            switch(this.idlField.datatype) {
                case 'bool':
                    switch(value) {
                        case 'true': return 't';
                        case 'on': return 't';
                        case 'false' : return 'f';
                        case 'unset' : return null;
                        case true : return 't';
                        default: return 'f';
                    }
                case 'timestamp':
                    if(!value) return null;
                    return dojo.date.stamp.toISOString(value);
                case 'int':
                case 'float':
                case 'money':
                    if(isNaN(value)) value = null;
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
            if(this.inherits) {
                switch(value) {
                    case null :
                    case undefined :
                    case 'unset' :
                        return openils.widget.AutoFieldWidget.localeStrings.INHERITED;
                }
            }
            switch(this.idlField.datatype) {
                case 'bool':
                    switch(value) {
                        case 't': 
                        case 'true': 
                            return openils.widget.AutoFieldWidget.localeStrings.TRUE; 
                        case 'f' : 
                        case 'false' : 
                            return openils.widget.AutoFieldWidget.localeStrings.FALSE;
                        case  null :
                        case 'unset' : return openils.widget.AutoFieldWidget.localeStrings.UNSET;
                        case true : return openils.widget.AutoFieldWidget.localeStrings.TRUE; 
                        default: return openils.widget.AutoFieldWidget.localeStrings.FALSE;
                    }
                case 'timestamp':
                    if (!value) return '';
                    return openils.Util.timeStamp(
                        value, {"formatLength": "short"}
                    );
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

        isRequired : function() {
            return (
                !this.readOnly && (
                    this.idlField.required || (
                        this.dijitArgs && (
                            this.dijitArgs.required || this.dijitArgs.regExp
                        )
                    )
                )
            );
        },

        build : function(onload) {

            if(this.widgetValue == null)
                this.widgetValue = (this.fmObject) ? this.fmObject[this.idlField.name]() : null;

            if(this.widget) {
                // core widget provided for us, attach and move on
                if(this.parentNode) // may already be in the "right" place
                    this.parentNode.appendChild(this.widget.domNode);
                if (this.shove) {
                    if (this.shove.mode == "update") {
                        if (this.idlField.datatype == "timestamp")
                            this.widgetValue = openils.Util.timeStampAsDateObj(
                                this.widgetValue
                            );
                    } else {
                        this.widgetValue = this.shove.create;
                    }
                    this._widgetLoaded();
                } else if (this.widget.attr("value") == null) {
                    this._widgetLoaded();
                }
                return;
            }
            
            if(!this.parentNode) // give it somewhere to live so that dojo won't complain
                this.parentNode = dojo.create('div');

            this.onload = onload;

            if(this.readOnly) {
                dojo.require('dijit.layout.ContentPane');
                this.widget = new dijit.layout.ContentPane(this.dijitArgs, this.parentNode);
                if(this.widgetValue !== null)
                    this._tryLinkedDisplayField();

            } else if(this.widgetClass) {
                dojo.require(this.widgetClass);
                eval('this.widget = new ' + this.widgetClass + '(this.dijitArgs, this.parentNode);');

            } else {

                switch(this.idlField.datatype) {
                    
                    case 'id':
                        dojo.require('dijit.form.TextBox');
                        this.widget = new dijit.form.TextBox(this.dijitArgs, this.parentNode);
                        break;

                    case 'org_unit':
                        this._buildOrgSelector();
                        break;

                    case 'money':
                        // dojo.require('dijit.form.CurrencyTextBox');
                        // the CurrencyTextBox dijit is broken in Dojo 1.3; upon upgrading
                        // to Dojo 1.5 or later, should re-evaluate work-around use of dijit.form.NumberTextBox.
                        // See https://bugs.launchpad.net/evergreen/+bug/702117
                        dojo.require('dijit.form.NumberTextBox');
                        this.dijitArgs = dojo.mixin({constraints:{places:'0,2'}}, this.dijitArgs || {});
                        this.widget = new dijit.form.NumberTextBox(this.dijitArgs, this.parentNode);
                        break;

                    case 'int':
                        dojo.require('dijit.form.NumberTextBox');
                        this.dijitArgs = dojo.mixin({constraints:{places:0}}, this.dijitArgs || {});
                        this.widget = new dijit.form.NumberTextBox(this.dijitArgs, this.parentNode);
                        break;

                    case 'float':
                        dojo.require('dijit.form.NumberTextBox');
                        this.widget = new dijit.form.NumberTextBox(this.dijitArgs, this.parentNode);
                        break;

                    case 'timestamp':
                        dojo.require('dijit.form.DateTextBox');
                        dojo.require('dojo.date.stamp');
                        if(!this.dijitArgs.constraints) {
                            this.dijitArgs.constraints = {};
                        }
                        if(!this.dijitArgs.constraints.datePattern) {
                            var user = new openils.User().user;
                            if(user.ws_ou()) {
                                var datePattern = fieldmapper.aou.fetchOrgSettingDefault(user.ws_ou(), 'format.date');
                                if(datePattern) this.dijitArgs.constraints.datePattern = datePattern.value;
                            }
                        }
                        this.widget = new dijit.form.DateTextBox(this.dijitArgs, this.parentNode);
                        if (this.widgetValue != null) {
                            this.widgetValue = openils.Util.timeStampAsDateObj(
                                this.widgetValue
                            );
                        }
                        break;

                    case 'bool':
                        if(this.ternary || this.inherits) {
                            dojo.require('dijit.form.FilteringSelect');
                            var store = new dojo.data.ItemFileReadStore({
                                data:{
                                    identifier : 'value',
                                    items:[
                                        {label : (this.inherits ? openils.widget.AutoFieldWidget.localeStrings.INHERITED : openils.widget.AutoFieldWidget.localeStrings.UNSET), value : 'unset'},
                                        {label : openils.widget.AutoFieldWidget.localeStrings.TRUE, value : 'true'},
                                        {label : openils.widget.AutoFieldWidget.localeStrings.FALSE, value : 'false'}
                                    ]
                                }
                            });
                            this.widget = new dijit.form.FilteringSelect(this.dijitArgs, this.parentNode);
                            this.widget.searchAttr = this.widget.labelAttr = 'label';
                            this.widget.valueAttr = 'value';
                            this.widget.store = store;
                            this.widget.startup();
                            this.widgetValue = (this.widgetValue === null) ? 'unset' : 
                                (openils.Util.isTrue(this.widgetValue)) ? 'true' : 'false';
                        } else {
                            dojo.require('dijit.form.CheckBox');
                            this.widget = new dijit.form.CheckBox(this.dijitArgs, this.parentNode);
                            this.widgetValue = openils.Util.isTrue(this.widgetValue);
                        }
                        break;

                    case 'link':
                        if(this._buildLinkSelector()) break;

                    default:
                        if(this.dijitArgs && (this.dijitArgs.required || this.dijitArgs.regExp)) {
                            dojo.require('dijit.form.ValidationTextBox');
                            this.widget = new dijit.form.ValidationTextBox(this.dijitArgs, this.parentNode);
                        } else {
                            dojo.require('dijit.form.TextBox');
                            this.widget = new dijit.form.TextBox(this.dijitArgs, this.parentNode);
                        }
                }
            }

            if(!this.async) this._widgetLoaded();
            return this.widget;
        },

        // we want to display the value for our widget.  However, instead of displaying
        // an ID, for exmaple, display the value for the 'selector' field on the object
        // the ID points to
        _tryLinkedDisplayField : function(noAsync) {

            if(this.idlField.datatype == 'org_unit')
                return false; // we already handle org_units, no need to re-fetch

            // user opted to bypass fetching this linked data
            if(this.suppressLinkedFields.indexOf(this.idlField.name) > -1)
                return false;

            var linkInfo = this._getLinkSelector();
            if(!(linkInfo && linkInfo.vfield && linkInfo.vfield.selector)) 
                return false;
            var lclass = linkInfo.linkClass;

            if(lclass == 'aou') 
                return false;

            // first try the store cache
            var self = this;
            if(this.cache[this.auth].list[lclass]) {
                var store = this.cache[this.auth].list[lclass];
                var query = {};
                query[linkInfo.vfield.name] = ''+this.widgetValue;
                var found = false;
                store.fetch({query:query, onComplete:
                    function(list) {
                        if(list[0]) {
                            var item = list[0];
                            if(self.labelFormat) {
                                self.widgetValue = self._applyLabelFormat(item, self.labelFormat);
                            } else {
                                self.widgetValue = store.getValue(item, linkInfo.vfield.selector);
                            }
                            found = true;
                        }
                    }
                });

                if(found) return;
            }

            // then try the single object cache
            var item;
            if(this.cache[this.auth].single[lclass] && (
                item = this.cache[this.auth].single[lclass][this.widgetValue]) ) {

                this.widgetValue = (this.labelFormat) ? 
                    this._applyLabelFormat(item.toStoreItem(), this.labelFormat) :
                    item[linkInfo.vfield.selector]();

                return;
            }

            console.log("Fetching linked object " + lclass + " : " + this.widgetValue);

            // if those fail, fetch the linked object
            this.async = true;
            var self = this;
            new openils.PermaCrud().retrieve(lclass, this.widgetValue, {   
                async : !this.forceSync,
                oncomplete : function(r) {
                    var item = openils.Util.readResponse(r);

                    // cache the true object under its real value
                    if(!self.cache[self.auth].single[lclass])
                        self.cache[self.auth].single[lclass] = {};
                    self.cache[self.auth].single[lclass][self.widgetValue] = item;

                    self.widgetValue = (self.labelFormat) ? 
                        self._applyLabelFormat(item.toStoreItem(), self.labelFormat) :
                        item[linkInfo.vfield.selector]();

                    self.widget.startup();
                    self._widgetLoaded();
                }
            });
        },

        _getLinkSelector : function() {
            var linkClass = this.idlField['class'];
            if(this.idlField.reltype != 'has_a')  return false;
            if(!fieldmapper.IDL.fmclasses[linkClass]) // class neglected by AutoIDL
                fieldmapper.IDL.load([linkClass]);
            if(!fieldmapper.IDL.fmclasses[linkClass].permacrud) return false;
            if(!fieldmapper.IDL.fmclasses[linkClass].permacrud.retrieve) return false;

            var vfield;
            var rclassIdl = fieldmapper.IDL.fmclasses[linkClass];

            for(var f in rclassIdl.fields) {
                if(this.idlField.key == rclassIdl.fields[f].name) {
                    vfield = rclassIdl.fields[f];
                    break;
                }
            }

            if(!vfield) 
                throw new Error("'" + linkClass + "' has no '" + this.idlField.key + "' field!");

            return {
                linkClass : linkClass,
                vfield : vfield
            };
        },

        _applyLabelFormat : function (item, formatList) {

            try {

                // formatList[1..*] are names of fields.  Pull the field
                // values from each object to determine the values for string substitution
                var values = [];
                var format = formatList[0];
                for(var i = 1; i< formatList.length; i++) 
                    values.push(item[formatList[i]]);

                return dojo.string.substitute(format, values);

            } catch(E) {
                throw new Error(
                    "openils.widget.AutoFieldWidget: Invalid formatList ["+formatList+"] : "+E);
            }
        },

        _buildLinkSelector : function() {
            var self = this;
            var selectorInfo = this._getLinkSelector();
            if(!selectorInfo) return false;

            var linkClass = selectorInfo.linkClass;
            var vfield = selectorInfo.vfield;

            this.async = true;

            if(linkClass == 'pgt')
                return this._buildPermGrpSelector();
            if(linkClass == 'aou')
                return this._buildOrgSelector();
            if(linkClass == 'acpl')
                return this._buildCopyLocSelector();
            if(linkClass == 'acqpro')
                return this._buildAutoCompleteSelector(linkClass, vfield.selector);


            dojo.require('dojo.data.ItemFileReadStore');
            dojo.require('dijit.form.FilteringSelect');

            this.widget = new dijit.form.FilteringSelect(this.dijitArgs, this.parentNode);
            this.widget.searchAttr = this.widget.labelAttr = vfield.selector || vfield.name;
            this.widget.valueAttr = vfield.name;
            this.widget.attr('disabled', true);

            var oncomplete = function(list) {
                self.widget.attr('disabled', false);

                if(self.labelFormat) 
                    self.widget.labelAttr = '_label';

                if(self.searchFormat)
                    self.widget.searchAttr = '_search';

                if(list) {
                    var storeData = {data:fieldmapper[linkClass].toStoreData(list)};

                    if(self.labelFormat) {
                        dojo.forEach(storeData.data.items, 
                            function(item) {
                                item._label = self._applyLabelFormat(item, self.labelFormat);
                            }
                        );
                    }

                    if(self.searchFormat) {
                        dojo.forEach(storeData.data.items, 
                            function(item) {
                                item._search = self._applyLabelFormat(item, self.searchFormat);
                            }
                        );
                    }

                    self.widget.store = new self.storeConstructor(storeData);
                    self.cache[self.auth].list[linkClass] = self.widget.store;

                } else {
                    self.widget.store = self.cache[self.auth].list[linkClass];
                }

                self.widget.startup();
                self._widgetLoaded();
            };

            if(!this.noCache && this.cache[self.auth].list[linkClass]) {
                oncomplete();

            } else {

                if(!this.dataLoader && openils.widget.AutoFieldWidget.defaultLinkedDataLoader[linkClass])
                    this.dataLoader = openils.widget.AutoFieldWidget.defaultLinkedDataLoader[linkClass];

                if(this.dataLoader) {

                    // caller provided an external function for retrieving the data
                    this.dataLoader(linkClass, this.searchFilter, oncomplete);

                } else {

                    var _cb = function(r) {
                        oncomplete(openils.Util.readResponse(r, false, true));
                    };

                    /* XXX LFW: I want to uncomment the following three lines that refer to ob, but haven't had the time to properly test. */

                    //var ob = {};
                    //ob[linkClass] = vfield.selector || vfield.name;

                    this.searchOptions = dojo.mixin(
                        {
                            async : !this.forceSync,
                            oncomplete : _cb
                            //order_by : ob
                        }, this.searchOptions
                    );

                    if (this.searchFilter) {
                        new openils.PermaCrud().search(linkClass, this.searchFilter, this.searchOptions);
                    } else {
                        new openils.PermaCrud().retrieveAll(linkClass, this.searchOptions);
                    }
                }
            }

            return true;
        },

        /**
         * For widgets that run asynchronously, provide a callback for finishing up
         */
        _widgetLoaded : function(value) {
            
            if(this.readOnly) {

                /* -------------------------------------------------------------
                   when using widgets in a grid, the cell may dissapear, which 
                   kills the underlying DOM node, which causes this to fail.
                   For now, back out gracefully and let grid getters use
                   getDisplayString() instead
                  -------------------------------------------------------------*/
                try { 
                    this.baseWidgetValue(this.getDisplayString());
                } catch (E) {};

            } else {

                this.baseWidgetValue(this.widgetValue);
                if(this.idlField.name == this.fmIDL.pkey && this.fmIDL.pkey_sequence && (!this.selfReference && !this.noDisablePkey))
                    this.widget.attr('disabled', true); 
                if(this.disableWidgetTest && this.disableWidgetTest(this.idlField.name, this.fmObject))
                    this.widget.attr('disabled', true); 
            }
            if(this.onload)
                this.onload(this.widget, this);

            if(!this.readOnly && (this.idlField.required || (this.dijitArgs && this.dijitArgs.required))) {
                // a required dijit is not given any styling to indicate the value
                // is invalid until the user has focused the widget then left it with
                // invalid data.  This change tells dojo to pretend this focusing has 
                // already happened so we can style required widgets during page render.
                this.widget._hasBeenBlurred = true;
                if(this.widget.validate)
                    this.widget.validate();
            }
        },

        _buildOrgSelector : function() {
            dojo.require('fieldmapper.OrgUtils');
            dojo.require('openils.widget.FilteringTreeSelect');
            this.widget = new openils.widget.FilteringTreeSelect(this.dijitArgs, this.parentNode);
            this.widget.searchAttr = this.searchAttr || 'shortname';
            this.widget.labelAttr = this.searchAttr || 'shortname';
            this.widget.parentField = 'parent_ou';
            var user = new openils.User();

            if(this.widgetValue == null && this.orgDefaultsToWs) 
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

            return true;
        },

        _buildPermGrpSelector : function() {
            dojo.require('openils.widget.FilteringTreeSelect');
            this.widget = new openils.widget.FilteringTreeSelect(this.dijitArgs, this.parentNode);
            this.widget.disableQuery = this.disableQuery;
            this.widget.searchAttr = 'name';

            if(this.cache.permGrpTree) {
                this.widget.tree = this.cache.permGrpTree;
                this.widget.startup();
                this._widgetLoaded();
                return true;
            } 

            var self = this;
            this.async = true;
            new openils.PermaCrud().retrieveAll('pgt', {
                async : !this.forceSync,
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
        },

        _buildCopyLocSelector : function() {
            dojo.require('dijit.form.FilteringSelect');
            this.widget = new dijit.form.FilteringSelect(this.dijitArgs, this.parentNode);
            this.widget.searchAttr = this.widget.labalAttr = 'name';
            this.widget.valueAttr = 'id';

            if(this.cache.copyLocStore) {
                this.widget.store = this.cache.copyLocStore;
                this.widget.startup();
                this.async = false;
                return true;
            } 

            // my orgs
            var ws_ou = openils.User.user.ws_ou();
            var orgs = fieldmapper.aou.findOrgUnit(ws_ou).orgNodeTrail().map(function (i) { return i.id() });
            orgs = orgs.concat(fieldmapper.aou.descendantNodeList(ws_ou).map(function (i) { return i.id() }));

            var self = this;
            new openils.PermaCrud().search('acpl', {owning_lib : orgs}, {
                async : !this.forceSync,
                order_by : {"acpl": "name"},
                oncomplete : function(r) {
                    var list = openils.Util.readResponse(r, false, true);
                    if(!list) return;
                    self.widget.store = 
                        new self.storeConstructor({data:fieldmapper.acpl.toStoreData(list)});
                    self.cache.copyLocStore = self.widget.store;
                    self.widget.startup();
                    self._widgetLoaded();
                }
            });

            return true;
        },

        _buildAutoCompleteSelector : function(linkClass, searchAttr) {
            dojo.require("openils.widget.PCrudAutocompleteBox");
            dojo.mixin(this.dijitArgs, {
                fmclass : linkClass,
                searchAttr : searchAttr,
            });
            this.widget = new openils.widget.PCrudAutocompleteBox(this.dijitArgs, this.parentNode);
            this._widgetLoaded();
            return true;
        }
    });

    openils.widget.AutoFieldWidget.localeStrings = dojo.i18n.getLocalization("openils.widget", "AutoFieldWidget");
    openils.widget.AutoFieldWidget.cache = {};
    openils.widget.AutoFieldWidget.defaultLinkedDataLoader = {};

}

