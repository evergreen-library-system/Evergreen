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
                this.dataList = [];
                var self = this;
                dojo.forEach(this.tree, function(node) { self._makeNodeList(node); });
                this.store = new dojo.data.ItemFileReadStore(
                    {data:fieldmapper[this.dataList[0].classname].toStoreData(this.dataList)});
                this.inherited(arguments);
            },

            // Compile the tree down to a depth-first list of nodes
            _makeNodeList : function(node) {
                this.dataList.push(node);
                for(var i in node[this.childField]()) 
                    this._makeNodeList(node[this.childField]()[i]);
            },

            // For each item, find the depth at display time by searching up the tree.
            _getMenuLabelFromItem : function(item) {
                var pad = -this.defaultPad;
                var self = this;

                function processItem(list) {
                    if(!list.length) return;
                    var pitem = list[0];
                    pad += self.defaultPad;
                    var parentId = self.store.getValue(pitem, self.parentField);
                    self.store.fetch({onComplete:processItem, query:{id:''+parentId}});
                }
                processItem([item]);

                return {
                    html: true,
                    label: '<div style="padding-left:'+pad+'px;">' +
                        this.store.getValue(item, this.labelAttr) + '</div>'
                }
            }
        }
    );
}
