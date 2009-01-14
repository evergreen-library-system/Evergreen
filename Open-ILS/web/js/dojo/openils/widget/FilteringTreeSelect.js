/* EXAMPLES:

<div dojoType="openils.widget.FilteringTreeSelect" tree="orgTree" parentField="parent_ou" searchAttr="shortname"/>
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
            valueField : '',
            tree : "",
            options : [],
            values : [],

            startup : function () {
                this.labelAttr = '_label'; // force it
                this.labelType = 'html'; // force it

                this._tree = (typeof this.tree == 'string') ? 
                        dojox.jsonPath.query(window, '$.' + this.tree, {evalType:"RESULT"}) : this.tree;
                if (!dojo.isArray(this._tree)) this._tree = [ this._tree ];

                this._datalist = [];
                if (!this.valueField) this.valueField = this._tree[0].Identifier;
                if (!this.searchAttr) this.searchAttr = this.valueField;

                var self = this;
                this._tree.forEach( function (node) { self._add_items( node, 0 ); } );

                this.store = new dojo.data.ItemFileReadStore({
                    data : {
                        identifier : this.valueField,
                        label : this.labelAttr,
                        items : this._datalist
                    }
                });

                this.inherited(arguments);
            },

            _add_items : function ( node, depth ) {
                var lpad = this.defaultPad * depth++;

                var data = node.toStoreItem();
                data._label = '<div style="padding-left:'+lpad+'px;">' + node[this.searchAttr]() + '</div>';

                this._datalist.push( data );

                var kids = node[this.childField]();
                for (var j in kids) {
                    this._add_items( kids[j], depth );
                }

                return null;
            }
        }
    );
}
