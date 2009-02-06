if(!dojo._hasResource["fieldmapper.IDL"]) {
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
            var classes = xmlNode.getElementsByTagName('class');
            var idl = fieldmapper.IDL.fmclasses = {};
    
            for(var i = 0; i < classes.length; i++) {
                var node = classes[i];
                var id = node.getAttribute('id');
                var fields = node.getElementsByTagName('fields')[0];
                window.fmclasses[id] = [];
    
                var obj = { 
                    fields  : this._parseFields(node, id),
                    name    : node.getAttribute('id'),
                    //table   : node.getAttributeNS(this.NS_PERSIST, 'tablename'),
                    //core    : node.getAttributeNS(this.NS_REPORTS, 'core'),
                    label   : node.getAttributeNS(this.NS_REPORTS, 'label'),
                    restrict_primary   : node.getAttributeNS(this.NS_PERSIST, 'restrict_primary'),
                    virtual : (node.getAttributeNS(this.NS_PERSIST, 'virtual') == 'true'),
                    pkey    : fields.getAttributeNS(this.NS_PERSIST, 'primary')
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
            }
    
            if(callback)
                callback();
        },
    
        /* parses the links and fields portion of the IDL */
        _parseFields : function(node, classname) {
            var data = [];
    
            var fields = node.getElementsByTagName('fields')[0];
            fields = fields.getElementsByTagName('field');
    
            var links = node.getElementsByTagName('links')[0];
            if( links ) links = links.getElementsByTagName('link');
            else links = [];
    
    
            for(var i = 0; i < fields.length; i++) {
                var field = fields[i];
                var name = field.getAttribute('name');

                var obj = {
                    field : field,
                    name	: name,
                    label : field.getAttributeNS(this.NS_REPORTS,'label'),
                    datatype : field.getAttributeNS(this.NS_REPORTS,'datatype'),
                    primitive : field.getAttributeNS(this.NS_PERSIST,'primitive'),
                    selector : field.getAttributeNS(this.NS_REPORTS,'selector'),
                    array_position : parseInt(field.getAttributeNS(this.NS_OBJ,'array_position')),
                    type	: 'field',
                    virtual : (fields[i].getAttributeNS(this.NS_PERSIST, 'virtual') == 'true') 
                };

                obj.label = obj.label || obj.name;
                obj.datatype = obj.datatype || 'text';

                if (obj.array_position > 2)
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
            }
    
            /*
            data = data.sort(
                function(a,b) {
                    if( a.label > b.label ) return 1;
                    if( a.label < b.name ) return -1;
                    return 0;
                }
            );
            */
    
            return data;
        }

    });

    window.fmclasses = {};
    fieldmapper.IDL.load = function (callback, force) { return new fieldmapper.IDL(callback, force); };
    fieldmapper.IDL.loaded = false;

}

