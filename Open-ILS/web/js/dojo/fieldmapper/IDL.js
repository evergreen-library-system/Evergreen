if(!dojo._hasResource["fieldmapper.IDL"]) {
    dojo._hasResource['fieldmapper.IDL'] = true;
    dojo.require("DojoSRF");
    dojo.provide("fieldmapper.IDL");
    dojo.declare('fieldmapper.IDL', null, {
    
        _URL_PATH : '/reports/fm_IDL.xml',
        NS_REPORTS : 'http://open-ils.org/spec/opensrf/IDL/reporter/v1',
        NS_PERSIST : 'http://open-ils.org/spec/opensrf/IDL/persistence/v1',
        NS_OBJ : 'http://open-ils.org/spec/opensrf/IDL/objects/v1',

        constructor : function(classlist) {

            var preload = [];
            if (window._preload_fieldmapper_IDL) {
                if (!fieldmapper.IDL.fmclasses) fieldmapper.IDL.fmclasses = {};
                if (!window.fmclasses) window.fmclasses = {};

                for (var c in window._preload_fieldmapper_IDL) {
                    preload.push(c);
                    fieldmapper.IDL.fmclasses[c] = window._preload_fieldmapper_IDL[c];

                    window.fmclasses[c] = [];
                    dojo.forEach(fieldmapper.IDL.fmclasses[c].fields, function(obj){ window.fmclasses[c].push(obj.name); });

                    if (classlist && classlist.length)
                        classlist = dojo.filter(classlist, function(x){return x != c;});
                }

                fieldmapper.IDL.loaded = true;
                window._preload_fieldmapper_IDL = null;
            }

            if(!fieldmapper.IDL.fmclasses || !fieldmapper.IDL.fmclasses.length || (classlist && classlist.length)) {
                var idl_url = this._URL_PATH;

                if (classlist.length && (classlist.length > 1 || classlist[0] != '*')) {
                    idl_url += '?';

                    for (var i = 0; i < classlist.length; i++) {
                        var trim_class = classlist[i];
                        if (!trim_class) continue;
                        if (fieldmapper.IDL.fmclasses && fieldmapper.IDL.fmclasses[trim_class]) continue;

                        if (i > 0) idl_url += '&';
                        idl_url += 'class=' + trim_class;
                    }
                }
                        
                if( !idl_url.match(/\?$/) ) { // make sure we have classes that need loading

                    var self = this;
                    dojo.xhrGet({
                        url : idl_url,
                        handleAs : 'xml',
                        sync : true,
                        timeout : 10000,
                        headers : {"Accept-Language": OpenSRF.locale},
                        load : function (response) {
                            self._parse(response);
                            fieldmapper.IDL.loaded = true;
                        },
                        error : function (response) {
                            fieldmapper.IDL.loaded = false;
                            dojo.require('fieldmapper.fmall', true);
                        }
                    });
                }
            }
            dojo.require('fieldmapper.Fieldmapper'); 

            if (preload.length)
                dojo.forEach( classlist, function (c) { fieldmapper.vivicateClass(c); } );

            if (classlist && classlist.length)
                dojo.forEach( classlist, function (c) { fieldmapper.vivicateClass(c); } );
        },

        _parse : function(xmlNode) {
            var classes = dojo.query('class',xmlNode);
            if (!fieldmapper.IDL || !fieldmapper.IDL.fmclasses)
                fieldmapper.IDL.fmclasses = {};

            for(var i = 0; i < classes.length; i++) {
                var node = classes[i];
                var id = node.getAttribute('id');
                var fields = dojo.query('fields',node)[0];
                window.fmclasses[id] = [];
                
                var fieldData = this._parseFields(node, id);
    
                var obj = { 
                    fields  : fieldData.list,
                    field_map : fieldData.map,
                    name    : node.getAttribute('id'),
                    //table   : fieldmapper._getAttributeNS(node,this.NS_PERSIST, 'tablename'),
                    //core    : fieldmapper._getAttributeNS(node,this.NS_REPORTS, 'core'),
                    label   : fieldmapper._getAttributeNS(node,this.NS_REPORTS, 'label'),
                    restrict_primary   : fieldmapper._getAttributeNS(node,this.NS_PERSIST, 'restrict_primary'),
                    virtual : (fieldmapper._getAttributeNS(node,this.NS_PERSIST, 'virtual') == 'true'),
                    pkey    : fieldmapper._getAttributeNS(fields,this.NS_PERSIST, 'primary'),
                    pkey_sequence : fieldmapper._getAttributeNS(fields,this.NS_PERSIST, 'sequence')
                };

                var valid = fieldmapper._getAttributeNS(node,this.NS_OBJ, 'validate');
                if (valid) obj.validate = new RegExp( valid.replace(/\\/g, '\\\\') );

                var permacrud = dojo.query('permacrud',node)[0];
                if(permacrud) {
                    var actions = ['create', 'retrieve', 'update', 'delete'];
                    obj.permacrud = {};
                    for(var idx in actions) {
                        var action = actions[idx];
                        var pnode = dojo.query(action,permacrud)[0];
                        if(pnode) {
                            var permString = pnode.getAttribute('permission');
                            var permList = null;
                            if(permString)
                                permList = (permString.match(/ /)) ? permString.split(' ') : [permString];
 
                            var contextString = pnode.getAttribute('context_field');
                            var contextList = null;
                            if(contextString)
                                contextList = (contextString.match(/ /)) ? contextString.split(' ') : [contextString];
    
                            obj.permacrud[action] = { 
                                perms : permList,
                                localContextFields : contextList // need to add foreign context fields
                            }; // add more details as necessary
                        }
                    }
                }
    
                obj.core = (obj.core == 'true');
                obj.label = (obj.label) ? obj.label : obj.name;
                fieldmapper.IDL.fmclasses[id] = obj;
            }
    
        },
    
        /* parses the links and fields portion of the IDL */
        _parseFields : function(node, classname) {
            var data = [];
            var map = {};
    
            var fields = dojo.query('fields',node)[0];
            fields = dojo.query('field',fields);
    
            var links = dojo.query('links',node)[0];
            if( links ) links = dojo.query('link',links);
            else links = [];
    
    
            var position = 0;
            for(var i = 0; i < fields.length; i++) {
                var field = fields[i];
                var name = field.getAttribute('name');

                if(name == 'isnew' || name == 'ischanged' || name == 'isdeleted') 
                    continue;

                var obj = {
                    field : field,
                    name : name,
                    label : fieldmapper._getAttributeNS(field,this.NS_REPORTS,'label'),
                    datatype : fieldmapper._getAttributeNS(field,this.NS_REPORTS,'datatype'),
                    primitive : fieldmapper._getAttributeNS(field,this.NS_PERSIST,'primitive'),
                    selector : fieldmapper._getAttributeNS(field,this.NS_REPORTS,'selector'),
                    array_position : position++,
                    type : 'field',
                    virtual : (fieldmapper._getAttributeNS(fields[i],this.NS_PERSIST, 'virtual') == 'true'),
                    required : (fieldmapper._getAttributeNS(fields[i],this.NS_OBJ, 'required') == 'true'),
                    i18n : (fieldmapper._getAttributeNS(fields[i],this.NS_PERSIST, 'i18n') == 'true')
                };

                obj.label = obj.label || obj.name;
                obj.datatype = obj.datatype || 'text';

                window.fmclasses[classname].push(obj.name);
    
                var link = null;
                for(var l = 0; l < links.length; l++) {
                    if(links[l].getAttribute('field') == name) {
                        link = links[l];
                        break;
                    }
                }
    
                if(link) {
                    obj.type = 'link';
                    obj.key = link.getAttribute('key');
                    obj['class'] = link.getAttribute('class');
                    obj.reltype = link.getAttribute('reltype');
                } 
    
                data.push(obj);
                map[obj.name] = obj;
            }
    
            dojo.forEach(['isnew', 'ischanged', 'isdeleted'],
                function(name) {
                    var obj = {
                        name : name,
                        array_position : position++,
                        type : 'field',
                        virtual : true
                    };
                    data.push(obj);
                    map[obj.name] = obj;
                }
            );

            return { list : data, map : map };
        }

    });

    fieldmapper._getAttributeNS = function (node,ns,attr) {
        if (node.getAttributeNS) return node.getAttributeNS(ns,attr);
        return node.getAttribute(attr);
    };

    window.fmclasses = {};
    fieldmapper.IDL.load = function (list) {
        if (!list) list = [];
        return new fieldmapper.IDL(list);
    };
    fieldmapper.IDL.loaded = false;

    JSON2js.fallbackObjectifier = function (arg, key_name, val_name) {
        console.log("Firing IDL loader for " + arg[key_name]);
        fieldmapper.IDL.load([arg[key_name]]);
        return decodeJS(arg);
    };
 
}

