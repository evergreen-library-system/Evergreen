if(!dojo._hasResource["fieldmapper.IDL"]) {
    dojo.require("DojoSRF");
    dojo.provide("fieldmapper.IDL");
    dojo.declare('fieldmapper.IDL', null, {
    
        _URL_PATH : '/reports/fm_IDL.xml', // XXX locale?
        // -- just need to set up xmlent and use '/reports/'+OpenSRF.locale+'/fm_IDL.xml'
        NS_REPORTS : 'http://open-ils.org/spec/opensrf/IDL/reporter/v1',
        NS_PERSIST : 'http://open-ils.org/spec/opensrf/IDL/persistence/v1',
        NS_OBJ : 'http://open-ils.org/spec/opensrf/IDL/objects/v1',

        constructor : function(classlist) {

            if(!fieldmapper.IDL.fmclasses || (classlist && classlist.length)) {
                var idl_url = this._URL_PATH;

                if (classlist.length) {
                    idl_url += '?';

                    for (var i = 0; i < classlist.length; i++) {
                        var trim_class = classlist[i];
                        if (!trim_class) continue;

                        if (i > 0) idl_url += '&';
                        idl_url += 'class=' + trim_class;
                    }

                    JSON2js.fallbackObjectifier = function (arg, key_name, val_name) {
                        fieldmapper.IDL.load([key_name]);
                        return decodeJS(arg);
                    }
                    
                }
                        
                var self = this;
                dojo.xhrGet({
                    url : idl_url,
                    handleAs : 'xml',
                    sync : true,
                    timeout : 10000,
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

            dojo.require('fieldmapper.Fieldmapper'); 

            if (classlist && classlist.length)
                dojo.forEach( classlist, function (c) { fieldmapper.vivicateClass(c); } );
        },

        _parse : function(xmlNode) {
            var classes = xmlNode.getElementsByTagName('class');
            if (!fieldmapper.IDL || !fieldmapper.IDL.fmclasses)
                fieldmapper.IDL.fmclasses = {};

            for(var i = 0; i < classes.length; i++) {
                var node = classes[i];
                var id = node.getAttribute('id');
                var fields = node.getElementsByTagName('fields')[0];
                window.fmclasses[id] = [];
                
                var fieldData = this._parseFields(node, id);
    
                var obj = { 
                    fields  : fieldData.list,
                    field_map : fieldData.map,
                    name    : node.getAttribute('id'),
                    //table   : node.getAttributeNS(this.NS_PERSIST, 'tablename'),
                    //core    : node.getAttributeNS(this.NS_REPORTS, 'core'),
                    label   : node.getAttributeNS(this.NS_REPORTS, 'label'),
                    restrict_primary   : node.getAttributeNS(this.NS_PERSIST, 'restrict_primary'),
                    virtual : (node.getAttributeNS(this.NS_PERSIST, 'virtual') == 'true'),
                    pkey    : fields.getAttributeNS(this.NS_PERSIST, 'primary'),
                    pkey_sequence : fields.getAttributeNS(this.NS_PERSIST, 'sequence')
                };

                var permacrud = node.getElementsByTagName('permacrud')[0];
                if(permacrud) {
                    var actions = ['create', 'retrieve', 'update', 'delete'];
                    obj.permacrud = {};
                    for(var idx in actions) {
                        var action = actions[idx];
                        var pnode = permacrud.getElementsByTagName(action)[0];
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
    
            var fields = node.getElementsByTagName('fields')[0];
            fields = fields.getElementsByTagName('field');
    
            var links = node.getElementsByTagName('links')[0];
            if( links ) links = links.getElementsByTagName('link');
            else links = [];
    
    
            var position = 0;
            for(var i = 0; i < fields.length; i++) {
                var field = fields[i];
                var name = field.getAttribute('name');

                if(name == 'isnew' || name == 'ischanged' || name == 'isdeleted') 
                    continue;

                var obj = {
                    field : field,
                    name	: name,
                    label : field.getAttributeNS(this.NS_REPORTS,'label'),
                    datatype : field.getAttributeNS(this.NS_REPORTS,'datatype'),
                    primitive : field.getAttributeNS(this.NS_PERSIST,'primitive'),
                    selector : field.getAttributeNS(this.NS_REPORTS,'selector'),
                    array_position : position++,
                    type	: 'field',
                    virtual : (fields[i].getAttributeNS(this.NS_PERSIST, 'virtual') == 'true') 
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

    window.fmclasses = {};
    fieldmapper.IDL.load = function (list) { if (!list) list = []; return new fieldmapper.IDL(list); };
    fieldmapper.IDL.loaded = false;

}

