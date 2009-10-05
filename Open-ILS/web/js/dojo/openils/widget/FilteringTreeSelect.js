/* EXAMPLES:

<input jsId='ftree' dojoType="openils.widget.FilteringTreeSelect" searchAttr='shortname' labelAttr='shortname' tree='myTree'/>

--- OR --

var tree = new openils.widget.FilteringTreeSelect(null, parentDiv);
tree.searchAttr = 'shortname';
tree.labelAttr = 'shortname';
tree.parentField = 'parent_ou';
tree1.tree = fieldmapper.aou.globalOrgTree;
tree1.startup();

*/

if(!dojo._hasResource["openils.widget.FilteringTreeSelect"]){
    dojo.provide("openils.widget.FilteringTreeSelect");
    dojo.require("dijit.form.FilteringSelect");

    dojo.declare(
        "openils.widget.FilteringTreeSelect", [dijit.form.FilteringSelect], {

            defaultPad : 10,
            parentField : 'parent',
            labelAttr : 'name',
            childField : 'children',
            tree : null,

            startup : function() {
                this.tree = (typeof this.tree == 'string') ? 
                        dojox.jsonPath.query(window, '$.' + this.tree, {evalType:"RESULT"}) : this.tree;
                if(!this.tree) {
                    console.log("openils.widget.FilteringTreeSelect: Tree needed!");
                    return;
                }
                if(!dojo.isArray(this.tree)) this.tree = [this.tree];
                this.className = this.tree[0].classname;
                this.dataList = [];
                var self = this;
                dojo.forEach(this.tree, function(node) { self._makeNodeList(node); });
                if(this.dataList.length > 0) {
                    var storeData = fieldmapper[this.className].initStoreData();
                    storeData.items = this.dataList;
                    this.store = new dojo.data.ItemFileReadStore({data:storeData});
                }
                this.inherited(arguments);
            },

            // Compile the tree down to a depth-first list of dojo data items
            _makeNodeList : function(node, depth) {
                if(!depth) depth = 0;
                var storeItem = node.toStoreItem();
                storeItem._depth = depth++;
                this.dataList.push(storeItem);
                for(var i in node[this.childField]()) 
                    this._makeNodeList(node[this.childField]()[i], depth);
            },

            // For each item, find the depth at display time by searching up the tree.
            _getMenuLabelFromItem : function(item) {
                return {
                    html: true,
                    label: '<div style="padding-left:'+ (item._depth * this.defaultPad) +'px;">' +
                        this.store.getValue(item, this.labelAttr) + '</div>'
                }
            }
        }
    );
}
