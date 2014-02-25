dojo.require('dijit.Dialog');
dojo.require('dijit.form.Button');
dojo.require('dijit.form.FilteringSelect');
dojo.require('openils.PermaCrud');
dojo.require('openils.widget.AutoFieldWidget');

var recordAttrDefs = {};// full name => crad map
var codedValueMaps = {};// growing cache of id => ccvm
var compositeDef;       // the thing what we're building / editing
var nodeTree;           // internal composite attrs tree representation
var treeIndex = 0;      // internal composit attrs node index

var localeStrings = {}; // TODO: move to nls file
localeStrings.OR = "OR";
localeStrings.AND = "AND";
localeStrings.NOT = "NOT";

function drawPage() {
    console.log('fetching ccvm ' + ccvmId);

    var asyncReqs = 2;

    new openils.PermaCrud().retrieve('ccvm', ccvmId, {
        flesh : 1, 
        flesh_fields : {ccvm : ['composite_def', 'ctype']},
        oncomplete : function(r) {
            map = openils.Util.readResponse(r);

            // draw the names
            dojo.byId('attr-def-name').innerHTML = 
                map.ctype().label();
            dojo.byId('coded-value-map-name').innerHTML = 
                map.code() + ' / ' + map.value();

            dojo.byId('return-to-ccvm').onclick = function() {
                location.href = oilsBasePath + 
                '/conify/global/config/coded_value_map/' + 
                map.ctype().name();
            };

            // build a new def if needed
            compositeDef = map.composite_def();
            if (!compositeDef) {
                compositeDef = new fieldmapper.ccraed();
                compositeDef.isnew(true);
                compositeDef.coded_value(map.id());
            }
            if (!--asyncReqs) drawCompositDef();
        }
    });

    new openils.PermaCrud().retrieveAll('crad', {
        order_by : {crad : ['name']},
        oncomplete : function(r) {
            var defs = openils.Util.readResponse(r); 
            dojo.forEach(defs, function(def) {
                recordAttrDefs[def.name()] = def;
            });
            if (!--asyncReqs) drawCompositDef();
        }
    });
}

var fetchAttrs = [];
function drawCompositDef() {
    var defBlob = JSON2js(compositeDef.definition());

    importNodeTree(null, defBlob);

    if (fetchAttrs.length) {
        new openils.PermaCrud().search('ccvm', {'-or' : fetchAttrs}, {
            oncomplete : function(r) {
                var maps = openils.Util.readResponse(r);
                dojo.forEach(maps, function(map) {
                    codedValueMaps[map.id()] = map;
                });
                drawNodeTree();
            }
        });
    } else {
        drawNodeTree();
    }
}

// translate the DB-stored tree into a local structure
function importNodeTree(pnode, node) {
    if (!node) return;

    var newnode = {
        index : treeIndex++,
        pnode : pnode,
        children : []
    }

    if (pnode) {
        pnode.children.push(newnode);
    } else {
        fetchAttrs = [];
        nodeTree = newnode;
    }

    if (dojo.isArray(node)) { 
        newnode.or = true;
        dojo.forEach(node, function(n) { importNodeTree(newnode, n) });

    } else if (node._not) {
        newnode.not = true;
        importNodeTree(newnode, node._not);

    } else if (node._attr) {
        // list of attrs that we have to fetch for display
        fetchAttrs.push({'-and' : {ctype : node._attr, code : node._val}});

        newnode.attr = node._attr;
        newnode.val = node._val;

    } else {
        newnode.and = true;
        dojo.forEach(Object.keys(node).sort(), function(key) {
            importNodeTree(newnode, node[key]);
        });
    }
}

function byname(elm, name) {
    return dojo.query('[name=' + name + ']', elm)[0];
}
function findccvm(ctype, code) {
    for (var id in codedValueMaps) {
        var m = codedValueMaps[id];
        if (m.code() == code && m.ctype() == ctype) {
            return m;
        }
    }
    console.error('cannot find ccvm ' + ctype + ' : ' + code);
}

// render the local structure tree in the DOM
var nodeTemplate;
var nodeTbody;
function drawNodeTree(node) {

    if (!nodeTbody) {
        nodeTbody = dojo.byId('tree-container');
        nodeTemplate = nodeTbody.removeChild(dojo.byId('node-template'));
    } 

    var root = false;
    if (!node) {
        dojo.empty(nodeTbody);
        if (!nodeTree) {
            newTreeBtn.attr('disabled', false);
            delTreeBtn.attr('disabled', true);
            return;
        } else {
            node = nodeTree;
            root = true;
        }
    }

    newTreeBtn.attr('disabled', true);
    delTreeBtn.attr('disabled', false);

    var depth = -1;
    function d(node) {if (node) {depth++; d(node.pnode);}};
    d(node);

    node.element = nodeTemplate.cloneNode(true);
    var expression = '';

    var addLink = byname(node.element, 'add-child');
    var delLink = byname(node.element, 'del-child');
    addLink.setAttribute('index', node.index);
    delLink.setAttribute('index', node.index);

    if (node.or) {
        byname(node.element, 'attr').innerHTML = localeStrings.OR;

    } else if (node.and) {
        byname(node.element, 'attr').innerHTML = localeStrings.AND;

    } else if (node.not) {
        byname(node.element, 'attr').innerHTML = localeStrings.NOT;

    } else {
        dojo.addClass(addLink, 'hidden');

        byname(node.element, 'attr').innerHTML = 
            recordAttrDefs[node.attr].label() + ' (' + node.attr + ')';

        var map = findccvm(node.attr, node.val);
        byname(node.element, 'val').innerHTML = 
            map.value() + ' (' + map.code() + ')';

        dojo.removeClass(
            dojo.query('.invisible', node.element)[0], 'invisible');

        expression = map.value();
    }

    nodeTbody.appendChild(node.element);

    var nc = dojo.query('.node-column', node.element)[0];
    for (var i = 0; i < depth; i++) {
        nc.insertBefore(dojo.byId('tree-pad').cloneNode(true), nc.firstChild); 
    }

    if (node.attr) return expression;

    if (node.not) {
        if (node.children[0]) {
            expression = localeStrings.NOT + 
                ' ' + drawNodeTree(node.children[0]);
        }

    } else { // AND | OR

        if (!root) expression = '( ';
        for (var i = 0; i < node.children.length; i++) {
            expression += drawNodeTree(node.children[i]);
            if (i == node.children.length - 1) break;
            expression += ' ' + (node.or ? localeStrings.OR : 
                (node.and ? localeStrings.AND : localeStrings.NOT)) + ' ';
        }
        if (!root) expression += ' )';
    }

    if (root) {
        dojo.byId('tree-expression').innerHTML = expression;
    }

    return expression;
}

function findNode(index, node) {
    if (!node) node = nodeTree;
    if (node.index == index) return node;
    for (var i = 0; i < node.children.length; i++) {
        var n = findNode(index, node.children[i]);
        if (n) return n;
    }
}

var cradSelector;
function buildSelectors() {
    if (cradSelector) return;
    cradSelector = new openils.widget.AutoFieldWidget({
        fmClass : 'crad',
        selfReference : true,
        parentNode : 'new-data-crad-selector'
    });
    cradSelector.build(function(w, ww) {
        dojo.connect(w, 'onChange', function(val) { 
            dojo.byId('new-data-attr').checked = true;
            new openils.PermaCrud().search('ccvm', {ctype : val}, {
                oncomplete : function(r) {
                    var maps = openils.Util.readResponse(r);
                    var items = [];
                    dojo.forEach(maps, function(map) {
                        codedValueMaps[map.id()] = map;
                        items.push({
                            name : map.value() + ' (' + map.code() + ')', 
                            value : map.id()
                        });
                    });
                    ccvmSelector.store = new dojo.data.ItemFileReadStore({
                        data : {
                            identifier : 'value',
                            label : 'name',
                            items : items
                        }
                    });
                    ccvmSelector.startup();
                }
            });
        });
    });
}

function addChild(link) {
    buildSelectors();
    var ctxNode = link ? findNode(link.getAttribute('index')) : null;

    newDataSubmit.onClick = function(args) {
        var node = {
            index : treeIndex++,
            pnode : ctxNode,
            children : []
        };

        if (dojo.byId('new-data-and').checked) {
            node.and = true;
        } else if (dojo.byId('new-data-or').checked) {
            node.or = true;
        } else if (dojo.byId('new-data-not').checked) {
            node.not = true;
        } else {
            node.attr = cradSelector.widget.attr('value');
            node.val = codedValueMaps[ccvmSelector.attr('value')].code();
            if (!node.attr || !node.val) return;
        }

        newDataDialog.hide();

        // for visual clarity, push the non-boolean children to the front
        if (ctxNode) {
            if (node.and || node.or || node.not) {
                ctxNode.children.push(node);
            } else {
                ctxNode.children.unshift(node);
            }
        } else {
            // starting a new tree from scratch
            nodeTree = node; 
        }
        drawNodeTree();
    }

    dojo.byId('new-data-attr').checked = true;
    newDataDialog.show(); 
}

function delChild(link) {
    var node = findNode(link.getAttribute('index'));

    if (node.pnode) {
        for (var i = 0; i < node.pnode.children.length; i++) {
            var child = node.pnode.children[i];
            if (child.index == node.index) {
                node.pnode.children.splice(i, 1);
                break;
            }
        }
    } else {
        newTreeBtn.attr('disabled', false);
        delTreeBtn.attr('disabled', true);
        nodeTree = null;
    }

    drawNodeTree();
}

function delTree() {
    nodeTree = null;
    drawNodeTree(); // resets
    new openils.PermaCrud().eliminate(compositeDef);
    compositeDef.isnew(true);
    compositeDef.definition(null);
}

function saveTree() {
    var expression = exportTree();

    compositeDef.definition(js2JSON(expression))
    var pcrud = new openils.PermaCrud();
    saveTreeBtn.attr('disabled', true);

    var oncomplete = function(r) {
        openils.Util.readResponse(r);  // pickup any alerts
        saveTreeBtn.attr('disabled', false);
        compositeDef.isnew(false);
    }

    var pfunc = compositeDef.isnew() ? 'create' : 'update';
    pcrud[pfunc](compositeDef, {oncomplete : oncomplete});
}

function exportTree(node) {
    if (!node) node = nodeTree;

    if (node.attr) 
        return {_attr : node.attr, _val : node.val};

    if (node.not)
        // _not nodes may only have one child
        return {_not : exportTree(node.children[0])};

    var compiled;
    for (var i = 0; i < node.children.length; i++) {
        var child = node.children[i];
        if (!compiled) compiled = node.or ? [] : {};
        compiled[i] = exportTree(child);
    }

    return compiled;
}

openils.Util.addOnLoad(drawPage);
