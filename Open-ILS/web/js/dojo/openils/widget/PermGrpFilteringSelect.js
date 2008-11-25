if(!dojo._hasResource["openils.widget.PermGrpFilteringSelect"]){
    dojo._hasResource["openils.widget.PermGrpFilteringSelect"] = true;
    dojo.provide("openils.widget.PermGrpFilteringSelect");
    dojo.require("dijit.form.FilteringSelect");
    dojo.require('dojo.data.ItemFileReadStore');
    dojo.require('openils.Util');

    dojo.declare(
        "openils.widget.PermGrpFilteringSelect", [dijit.form.FilteringSelect], 
        {
            fetchGroups : function(onload) {

                if(this.groupTree) 
                    return onload();
                var self = this;

                fieldmapper.standardRequest(
                    ['open-ils.actor', 'open-ils.actor.groups.tree.retrieve'],
                    {   async: true,
                        oncomplete: function(r) {
                            self.groupTree = openils.Util.readResponse(r);
                            onload();
                        }
                    }
                );
            },

            flatten : function(node) {
                if(!node) {
                    node = this.groupTree;
                    this.groupMap = {};
                }
                this.groupMap[node.id()] = node;
                for(var idx in node.children())
                    this.flatten(node.children()[idx]);
            },
            
            drawGroups : function() {
                var self = this;
                this.fetchGroups(function(){self._drawGroups()});
            },

            _drawGroups : function(node, depth, list) {
                if(!node) { 
                    node = this.groupTree; 
                    list = []; 
                    depth = 0; 
                }

                lpad = 6 * depth;
                var data = pgt.toStoreData([node]).items[0];
                data._label = '<div style="padding-left:'+lpad+'px;">' + node.name() + '</div>';
                list.push(data);

                for(var idx in node.children()) 
                    this._drawGroups(node.children()[idx], depth + 1, list);

                if(depth == 0) {
                    var construct = {data : {identifier : 'id', items: list}};
                    this.store = new dojo.data.ItemFileReadStore(construct);
                    this.startup();
                }
            },

            _getMenuLabelFromItem : function(item) {
                return {
                    html: true,
                    label: item._label
                };
            }
        }
    );
}
