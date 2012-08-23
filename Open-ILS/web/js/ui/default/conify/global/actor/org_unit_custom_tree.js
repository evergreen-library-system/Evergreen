dojo.require('dijit.form.Button');
dojo.require('dijit.form.FilteringSelect');
dojo.require('dojo.data.ItemFileReadStore');
dojo.require('dojo.data.ItemFileWriteStore');
dojo.require('dijit.Tree');
dojo.require('dijit.tree.TreeStoreModel');
dojo.require("dijit._tree.dndSource");
dojo.require('fieldmapper.Fieldmapper');
dojo.require('fieldmapper.OrgUtils');
dojo.require('openils.User');
dojo.require('openils.Util');
dojo.require('openils.PermaCrud');
dojo.require('openils.widget.ProgressDialog');

var realTree; // dijit.Tree
var magicTree; // dijit.Tree
var mTree; // aouct object
var pcrud;
var virtId = -1;
var realOrgList = [];
var ctNodes = [];

dojo.declare(
    'openils.actor.OrgUnitCustomTreeSource', dijit._tree.dndSource, {
    itemCreator : function(nodes, etc) {
        var items = this.inherited(arguments);
        dojo.forEach(items, function(item) {item.shortname = item.name});
        return items;
    }
});

dojo.declare(
    'openils.actor.OrgUnitCustomTreeStoreModel', dijit.tree.TreeStoreModel, {
    mayHaveChildren : function(item) { return true },
});

function drawPage() {
    pcrud = new openils.PermaCrud({authtoken : openils.User.authtoken});

    // real org unit list.  Not write-able.  Used only as a source.
    realOrgList = openils.Util.objectValues(
        fieldmapper.aou.OrgCache).map(function(obj) { return obj.org });

    var store = new dojo.data.ItemFileReadStore(
        {data : fieldmapper.aou.toStoreData(realOrgList)});
            
    var model = new dijit.tree.TreeStoreModel({
        store: store,
        query: {_top : 'true'}
    });

    realTree = new dijit.Tree(
        {   model: model,
            expandAll: function() {treeDoAll(this)},
            collapseAll: function() {treeDoAll(this, true)},
            dndController : dijit._tree.dndSource,
            persist : false,
        }, 
        'real-tree'
    );

    realTree.expandAll();
    drawMagicTree();
}


// composed of org units.  Write-able.
function drawMagicTree() {
    var orgList = realOrgList;
    var query = {_top : 'true'};

    var mTreeRes = pcrud.search('aouct', 
        {purpose : treePurposeSelector.attr('value')});

    if (mTreeRes.length) {
        mTree = mTreeRes[0];
        if (openils.Util.isTrue(mTree.active())) {
            openils.Util.hide(dojo.byId('activate-tree'));
            openils.Util.show(dojo.byId('deactivate-tree'), 'inline');
        }
        ctNodes = pcrud.search('aouctn', {tree : mTree.id()});
        if (ctNodes.length) {
            orgList = [];
            // create an org tree from the custom tree nodes
           
            dojo.forEach(ctNodes, 
                function(node) {
                    // deep clone to avoid globalOrgTree clobbering
                    var org = JSON2js(js2JSON( 
                        fieldmapper.aou.findOrgUnit(node.org_unit())
                    ));
                    org.parent_ou(null);
                    org.children([]);
                    if (node.parent_node()) {
                        org.parent_ou(
                            ctNodes.filter(
                                function(n) {return n.id() == node.parent_node()}
                            )[0].org_unit()
                        );
                    }
                    orgList.push(org);
                }
            );
            var root = ctNodes.filter(function(n) {return n.parent_node() == null})[0];
            query = {id : root.org_unit()+''}
        }
    } else {

        mTree = new fieldmapper.aouct();
        mTree.isnew(true);
        mTree.purpose(treePurposeSelector.attr('value'));
        mTree.active(false);
    }

    var store = new dojo.data.ItemFileWriteStore(
        {data : fieldmapper.aou.toStoreData(orgList)});

    var model = new openils.actor.OrgUnitCustomTreeStoreModel({
        store : store,
        query : query
    });

    magicTree = new dijit.Tree(
        {   model: model,
            expandAll: function() {treeDoAll(this)},
            collapseAll: function() {treeDoAll(this, true)},
            dndController : openils.actor.OrgUnitCustomTreeSource,
            dragThreshold : 8,
            betweenThreshold : 5,
            persist : false,
        }, 
        'magic-tree'
    );

    magicTree.expandAll();
}

// 1. create the tree if necessary
// 2. translate the dijit.tree nodes into aouctn's
// 3. delete the existing aouctn's
// 4. create the new aouctn's
function applyChanges() {
    progressDialog.show();

    if (mTree.isnew()) {

        pcrud.create(mTree, {
            oncomplete : function(r, objs) {
                mTree = objs[0];
                applyChanges2();
            }
        });
    
    } else {
        if (ctNodes.length) { 
            console.log('Deleting ' + ctNodes.length + ' nodes');
            pcrud.eliminate(ctNodes, {oncomplete : applyChanges2});
        } else {
            applyChanges2();
        }
    }
}

function applyChanges2() {

    // pcrud.disconnect() exits before disconnecting the session.
    // Clean up the session here.  TODO: fix pcrud
    pcrud.session.disconnect();
    pcrud.session.cleanup();

    ctNodes = [];
    var newCtNodes = [];
    var nodeList = [];
    var sorder = 0;
    var prevTn;
    var progress = 0;
    var session = new OpenSRF.ClientSession('open-ils.pcrud');

    // flatten child nodes into a level-order (by parent) list
    var nodeList = [magicTree.rootNode];
    function flatten(node) {
        var kids = node.getChildren();
        nodeList = nodeList.concat(kids);
        dojo.forEach(kids, flatten);
    }
    flatten(magicTree.rootNode);

    // called after all nodes are processed
    function finishUp() {
        // commit the transaction
        session.request({
            method : 'open-ils.pcrud.transaction.commit',
            params : [ openils.User.authtoken ],
            oncomplete : function (r) {
                session.disconnect();
                location.href = location.href;
            }
        }).send();
    }

    // traverse the nodes, creating new aoucnt's as we go
    function traverseAndCreate(node) {
        var item = node.item;

        var tn = new fieldmapper.aouctn();
        tn.tree(mTree.id());
        tn.org_unit(item.id[0])

        var pnode = node.getParent();
        if (pnode) {
            // find the newly created parent node and extract the ID 
            var ptn = ctNodes.filter(function(n) {
                return n.org_unit() == pnode.item.id[0]})[0];
            tn.parent_node(ptn.id());
        }

        // if the last node was our previous sibling
        if (prevTn && prevTn.parent_node() == tn.parent_node()) {
            tn.sibling_order(++sorder);
        } else { sorder = 0; }

        // create the new node, then process the children (async)
        session.request({
            method : 'open-ils.pcrud.create.aouctn',
            params : [ openils.User.authtoken, tn ],
            oncomplete : function (r) {
                var newTn = openils.Util.readResponse(r);
                console.log("Created new node for org " + newTn.org_unit() + " => " + newTn.id());
                ctNodes.push(newTn);
                prevTn = newTn;
                if (nodeList.length == 0) {
                    finishUp();
                } else {
                    progressDialog.update({maximum : nodeList.length, progress : ++progress});
                    traverseAndCreate(nodeList.shift());
                }
            }
        }).send();
    }

    // kick things off...
    session.connect();

    // start the transaction
    session.request({
        method : 'open-ils.pcrud.transaction.begin',
        params : [ openils.User.authtoken ],
        oncomplete : function (r) {
            traverseAndCreate(nodeList.shift());
        }
    }).send();
}

function deleteSelected() {
    var toDelete = [];

    function collectChildren(item) {
        toDelete.push(item);
        magicTree.model.store.fetch({
            query : {parent_ou : item.id[0]+''},
            onComplete : function(list) { 
                dojo.forEach(list, collectChildren) 
            }
        });
    }

    magicTree.dndController.getSelectedItems().forEach(
        function(item) {
            if (item === magicTree.model.root) return
            collectChildren(item);
            // delete node plus children, starting at the leaf nodes
            dojo.forEach(toDelete.reverse(),
                function(i) {
                    console.log('Deleting item ' + i.id);
                    magicTree.model.store.deleteItem(i)
                }
            );
        }
    );

    // otherwise, delete is only superficial
    magicTree.model.store.save();
}

function activateTree() {
    mTree.active('t');

    if (mTree.isnew()) {
        // before the tree exists, we can only activate the local copy
        // the next save event will activate it
        openils.Util.hide(dojo.byId('activate-tree'));
        openils.Util.show(dojo.byId('deactivate-tree'), 'inline');
        return;
    }

    pcrud.update(mTree, {
        oncomplete : function() {
            openils.Util.hide(dojo.byId('activate-tree'));
            openils.Util.show(dojo.byId('deactivate-tree'), 'inline');
        }
    });
}

function deactivateTree() {
    mTree.active('f');

    if (mTree.isnew()) {
        openils.Util.hide(dojo.byId('deactivate-tree'));
        openils.Util.show(dojo.byId('activate-tree'), 'inline');
        return;
    }

    pcrud.update(mTree, {
        oncomplete : function() {
            openils.Util.hide(dojo.byId('deactivate-tree'));
            openils.Util.show(dojo.byId('activate-tree'), 'inline');
        }
    });
}

// modified from 
// http://stackoverflow.com/questions/2161032/expanding-all-nodes-in-dijit-tree
function treeDoAll(tree, collapse) {
    function expand(node) {
        if (collapse) tree._collapseNode(node);
        else tree._expandNode(node);
        var childBranches = dojo.filter(node.getChildren() || [], 
            function(node) { return node.isExpandable });
        var def = new dojo.Deferred();
        defs = dojo.map(childBranches, expand);
    }
    return expand(tree.rootNode);
}

openils.Util.addOnLoad(drawPage);
