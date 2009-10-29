if(!dojo._hasResource["fieldmapper.IDL"]) {
    dojo.require('dojox.data.dom');
    dojo.provide("fieldmapper.IDL");
    dojo.declare('fieldmapper.IDL', null, {
    
        _URL_PATH : '/reports/fm_IDL.xml', // XXX locale?
        // -- just need to set up xmlent and use '/reports/'+dojo.locale+'/fm_IDL.xml'
        NS_REPORTS : 'http://open-ils.org/spec/opensrf/IDL/reporter/v1',
        NS_PERSIST : 'http://open-ils.org/spec/opensrf/IDL/persistence/v1',
        NS_OBJ : 'http://open-ils.org/spec/opensrf/IDL/objects/v1',

        constructor : function(callback, force) {
            if(!fieldmapper.IDL.fmclasses || force) {
                var self = this;
                dojo.xhrGet({
                    url : this._URL_PATH,
                    handleAs : 'xml',
                    sync : true,
                    timeout : 10000,
                    load : function (response) {
                        self._parse(response, callback);
                        fieldmapper.IDL.loaded = true;
                    },
                    error : function (response) {
                        fieldmapper.IDL.loaded = false;
                        dojo.require('fieldmapper.fmall', true);
                        if(callback)
                            callback();
                    }
                });
            }

            return dojo.require('fieldmapper.Fieldmapper');
        },

        _parse : function(xmlNode, callback) {
            var idl = fieldmapper.IDL.fmclasses = {};

            dojo.forEach( dojo.query('class', xmlNode), function (node) {
                var id = node.getAttribute('id');
                var fields = dojo.query('fields', node)[0];
                window.fmclasses[id] = [];
                
                var fieldData = this._parseFields( node, id );
    
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
                idl[id] = obj;
            });
    
            if(callback) callback();
        },
    
        /* parses the links and fields portion of the IDL */
        _parseFields : function(node, classname) {
            var data = [];
            var map = {};
    
            var links = dojo.query('links', node);
    
            var position = 0;
            dojo.forEach(dojo.query('fields field', node), function (field) {
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
                    virtual : (field.getAttributeNS(this.NS_PERSIST, 'virtual') == 'true') 
                };

                obj.label = obj.label || obj.name;
                obj.datatype = obj.datatype || 'text';

                window.fmclasses[classname].push(obj.name);
    
                var link = dojo.query('links link[field=' + name + ']', node)[0];
                if(link) {
                    obj.type = 'link';
                    obj.key = link.getAttribute('key');
                    obj['class'] = link.getAttribute('class');
                    obj.reltype = link.getAttribute('reltype');
                } 
    
                data.push(obj);
                map[obj.name] = obj;
            });
    
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
    fieldmapper.IDL.load = function (callback, force) { return new fieldmapper.IDL(callback, force); };
    fieldmapper.IDL.loaded = false;

}

