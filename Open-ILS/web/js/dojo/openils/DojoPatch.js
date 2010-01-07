if(!dojo._hasResource["openils.DojoPatch"]) {

    dojo.provide("openils.DojoPatch");
    //dojo.declare('openils.dojoPatch', null);
    
    
    if(dojo.version.major == 1 && dojo.version.minor < 3) {
        // a copy of dojo.create, from svn trunk's dojo/_base/html.js
        // lots of useful doc comments snipped for brevity
        dojo.create = function(tag, attrs, refNode, pos) {
            var doc = d.doc;
            if(refNode){		
                refNode = d.byId(refNode);
                doc = refNode.ownerDocument;
            }
            if(d.isString(tag)){
                tag = doc.createElement(tag);
            }
            if(attrs){ d.attr(tag, attrs); }
            if(refNode){ d.place(tag, refNode, pos); }
            return tag; // DomNode
        }
    };
}

       

        