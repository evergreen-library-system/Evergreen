/* EXAMPLES:

<div dojoType="openils.widget.FilteringTreeSelect" tree="orgTree" parentField="parent_ou" nameField="shortname"/>
<div dojoType="openils.widget.FilteringTreeSelect" tree="grpTree"/>

The tree attribute is expected to be a tree-shaped pile of OpenSRF objects.

*/

if(!dojo._hasResource["openils.widget.FilteringTreeSelect"]){
    dojo.provide("openils.widget.FilteringTreeSelect");
    dojo.require("dijit.form.FilteringSelect");
    dojo.require('dojo.data.ItemFileReadStore');
    dojo.require('openils.Util');
    dojo.require("dojox.jsonPath");

    dojo.declare(
        "openils.widget.FilteringTreeSelect", [dijit.form.ComboBox], 
        {

            defaultPad : 6,
            childField : 'children',
            parentField : 'parent',
            nameField : 'name',
            valueField : '',
            tree : "",
            options : [],
            values : [],

            startup : function () {
                this._tree = dojox.jsonPath.query(window, '$.' + this.tree, {evalType:"RESULT"});
                this._datalist = [];
                if (!this.valueField) this.valueField = this._tree.Identifier;

                this._add_items( this._tree, 0 );

                var construct = {data : {identifier : this.valueField, items: this.datalist}};
                this.store = new dojo.data.ItemFileReadStore(construct);

                this.inherited(arguments);
            },

            _add_items : function ( node, depth ) {
                var lpad = this.defaultPad * depth++;

                var data = node.toStoreData();
                data._label = '<div style="padding-left:'+lpad+'px;">' + node[this.nameField]() + '</div>';

                this._datalist.push( data );

                var kids = node[this.childField]();
                for (var j in kids) {
                    this._add_items( kids[j], depth );
                }

                return null;
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
