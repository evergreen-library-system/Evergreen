dojo.require("dijit.Tree");
dojo.require("dijit.form.Button");
dojo.require("dojo.data.ItemFileWriteStore");
//dojo.require("openils.vandelay.DndSource");
dojo.require("dojo.dnd.Source");
dojo.require("openils.vandelay.TreeDndSource");
dojo.require("openils.vandelay.TreeStoreModel");
dojo.require("openils.CGI");
dojo.require("openils.User");
dojo.require("openils.Util");
dojo.require("openils.PermaCrud");
dojo.require("openils.widget.ProgressDialog");

var localeStrings, node_editor, _crads, CGI, tree;

function _find_crad_by_name(name) {
    for (var i = 0; i < _crads.length; i++) {
        if (_crads[i].name() == name)
            return _crads[i];
    }
    return null;
}

function NodeEditor() {
    var self = this;

    var _svf_select_template = null;
    var _factories_by_type = {
        "svf": function() {
            if (!_svf_select_template) {
                _svf_select_template = dojo.create(
                    "select", {"fmfield": "svf"}
                );
                for (var i=0; i<_crads.length; i++) {
                    dojo.create(
                        "option", {
                            "value": _crads[i].name(),
                            "innerHTML": _crads[i].label()
                        }, _svf_select_template
                    );
                }
            }

            var select = dojo.clone(_svf_select_template);
            dojo.attr(select, "id", "svf-select");
            var label = dojo.create(
                "label", {
                    "for": "svf-select", "innerHTML": "Single-Value-Field:"
                }
            );

            var tr = dojo.create("tr");
            dojo.place(label, dojo.create("td", null, tr));
            dojo.place(select, dojo.create("td", null, tr));

            return [tr];
        },
        "tag": function() {
            var rows = [dojo.create("tr"), dojo.create("tr")];
            dojo.create(
                "label", {
                    "for": "tag-input", "innerHTML": "Tag:"
                }, dojo.create("td", null, rows[0])
            );
            dojo.create(
                "input", {
                    "id": "tag-input",
                    "type": "text",
                    "size": 4,
                    "maxlength": 3,
                    "fmfield": "tag"
                }, dojo.create("td", null, rows[0])
            );
            dojo.create(
                "label", {
                    "for": "subfield-input", "innerHTML": "Subfield: \u2021"
                }, dojo.create("td", null, rows[1])
            );
            dojo.create(
                "input", {
                    "id": "subfield-input",
                    "type": "text",
                    "size": 2,
                    "maxlength": 1,
                    "fmfield": "subfield"
                }, dojo.create("td", null, rows[1])
            );
            return rows;
        },
        "bool_op": function() {
            var tr = dojo.create("tr");
            dojo.create(
                "label",
                {"for": "operator-select", "innerHTML": "Operator:"},
                dojo.create("td", null, tr)
            );
            var select = dojo.create(
                "select", {"fmfield": "bool_op", "id": "operator-select"},
                dojo.create("td", null, tr)
            );
            dojo.create("option", {"value": "AND", "innerHTML": "AND"}, select);
            dojo.create("option", {"value": "OR", "innerHTML": "OR"}, select);

            return [tr];
        }
    };

    function _simple_value_getter(control) {
        if (typeof control.selectedIndex != "undefined")
            return control.options[control.selectedIndex].value;
        else if (dojo.attr(control, "type") == "checkbox")
            return control.checked;
        else
            return control.value;
    };

    this._init = function(dnd_source, node_editor_container) {
        this.dnd_source = dnd_source;
        this.node_editor_container = dojo.byId(node_editor_container);
    };

    this.clear = function() {
        this.dnd_source.selectAll().deleteSelectedNodes();
        dojo.empty(this.node_editor_container);
    };

    this.update_draggable = function(draggable) {
        var s = "";
        draggable.match_point = new vmsp();
        var had_op = false;
        dojo.query("[fmfield]", this.node_editor_container).forEach(
            function(control) {
                var used_svf = null;
                var field = dojo.attr(control, "fmfield");
                var value = _simple_value_getter(control);
                draggable.match_point[field](value);

                if (field == "subfield")
                    s += " \u2021";
                if (field == "svf")
                    used_svf = value;
                if (field == "quality")
                    return;
                if (field == "bool_op")
                    had_op = true;
                if (field == "negate") {
                    if (value) {
                        if (had_op)
                            s = "<strong>N</strong>" + s;
                        else
                            s = "<strong>NOT</strong> " + s;
                    }
                } else {
                    s += value;
                }

                if (used_svf !== null) {
                    var our_crad = _find_crad_by_name(used_svf);
                    /* XXX i18n, use fmtted strings */
                    s += " / " + our_crad.label() + "<br /><em>" +
                        (our_crad.description() || "") + "</em><br />";
                }
            }
        );
        dojo.attr(draggable, "innerHTML", s);
        this.dnd_source._ready = true;
    };

    this._add_consistent_controls = function(tgt) {
        if (!this._consistent_controls) {
            var trs = dojo.query("[consistent-controls]");
            this._consistent_controls = [];
            for (var i = 0; i < trs.length; i++)
                this._consistent_controls[i] = dojo.clone(trs[i]);
            dojo.empty(trs[0].parentNode);
        }

        this._consistent_controls.forEach(
            function(node) { dojo.place(dojo.clone(node), tgt); }
        );
    };

    this.add = function(type) {
        this.clear();

        /* a representation, not the editing widgets, but will also carry
         * the fieldmapper object when dragged to the tree */
        var draggable = dojo.create(
            "li", {"innerHTML": localeStrings.DEFINE_MP}
        );

        /* these are the editing widgets */
        var table = dojo.create("table", {"className": "node-editor"});

        var nodes = _factories_by_type[type]();
        for (var i = 0; i < nodes.length; i++) dojo.place(nodes[i], table);

        this._add_consistent_controls(table);

        dojo.create(
            "input", {
                "type": "submit", "value": "Ok",
                "onclick": function() { self.update_draggable(draggable); }
            }, dojo.create(
                "td", {"colspan": 2, "align": "center"},
                dojo.create("tr", null, table)
            )
        );

        dojo.place(table, this.node_editor_container, "only");
        /* XXX around here attach other data structures to the node */
        this.dnd_source.insertNodes(false, [draggable]);
        this.dnd_source._ready = false;
    };

    this._init.apply(this, arguments);
}

/* XXX replace later with code that will suit this function's purpose
 * as well as that of update_draggable. */
function display_name_from_point(point) {
    /* quick and dirty */
    if (point.bool_op()) {
        return (point.negate() == "t" ? "N" : "") + point.bool_op();
    } else if (point.svf()) {
        return (point.negate() == "t" ? "NOT " : "") + point.svf();
    } else {
        return (point.negate() == "t" ? "NOT " : "") + point.tag() +
            "\u2021" + point.subfield();
    }
}

function delete_selected_from_tree() {
    /* relies on the fact that we only have one tree that would have
     * registered a dnd controller. */
    _tree_dnd_controllers[0].getSelectedItems().forEach(
        function(item) {
            tree.model.store.deleteItem(item);
        }
    );
}

/* dojoize_match_set_tree() takes an argument, "point", that is actually a
 * vmsp fieldmapper object with descendants fleshed hierarchically. It turns
 * that into a syntactically flat array but preserving the hierarchy
 * semantically in the language used by dojo data stores, i.e.,
 *
 * [
 *  {'id': 'root', children:[{'_reference': '0'}, {'_reference': '1'}]},
 *  {'id': '0', children:[]},
 *  {'id': '1', children:[]}
 * ],
 *
 */
function dojoize_match_set_tree(point, refgen) {
    /* XXX TODO test with deeper trees! */
    var root = false;
    if (!refgen) {
        refgen = 0;
        root = true;
    }

    var bathwater = point.children();
    point.children([]);
    var item = {
        "id": (root ? "root" : refgen),
        "name": display_name_from_point(point),
        "match_point": point.clone(),
        "children": []
    };
    point.children(bathwater);

    var results = [item];

    if (point.children()) {
        for (var i = 0; i < point.children().length; i++) {
            var child = point.children()[i];
            item.children.push({"_reference": ++refgen});
            results = results.concat(
                dojoize_match_set_tree(child, refgen)
            );
        }
    }

    return results;
}

function render_match_set_description(match_set) {
    dojo.byId("vms-name").innerHTML = match_set.name();
    dojo.byId("vms-owner").innerHTML =
        aou.findOrgUnit(match_set.owner()).name();
    dojo.byId("vms-mtype").innerHTML = match_set.mtype();
}

function init_test() {
    progress_dialog.show(true);

    dojo.requireLocalization("openils.vandelay", "match_set");
    localeStrings = dojo.i18n.getLocalization("openils.vandelay", "match_set");

    pcrud = new openils.PermaCrud();
    CGI = new openils.CGI();

    var match_set = pcrud.retrieve("vms", CGI.param("match_set"));
    render_match_set_description(match_set);

    /* XXX No-one should have hundreds of these or anything, but theoretically
     * this could be problematic with a big enough list of crad objects. */
    _crads = pcrud.retrieveAll(
        "crad", {"order_by": {"crad": "label"}}
    );

    var match_set_tree = fieldmapper.standardRequest(
        ["open-ils.vandelay", "open-ils.vandelay.match_set.get_tree"],
        [openils.User.authtoken, CGI.param("match_set")]
    );

//        {
//            "identifier": "id", "label": "name", "items": [
//                {
//                    "id": "root", "name": "AND",
//                    "children": [
//                        {"_reference": "leaf0"}, {"_reference": "leaf1"}
//                    ]
//                },
//                {"id": "leaf0", "name": "nonsense test"},
//                {"id": "leaf1", "name": "more nonsense"}
//            ]
//        }

    var store = new dojo.data.ItemFileWriteStore({
        "data": {
            "identifier": "id",
            "label": "name",
            "items": dojoize_match_set_tree(match_set_tree)
        }
    });

    var treeModel = new openils.vandelay.TreeStoreModel({
        store: store, "query": {"id": "root"}
    });

    var src = new dojo.dnd.Source("src-here");
    tree = new dijit.Tree(
        {
            "model": treeModel,
            "dndController": openils.vandelay.TreeDndSource,
            "dragThreshold": 8,
            "betweenThreshold": 5,
            "persist": false
        }, "tree-here"
    );

    node_editor = new NodeEditor(src, "node-editor-container");

    dojo.connect(
        src, "onDndDrop", null,
        function(source, nodes, copy, target) {
            if (source == this) {
                var model = target.tree.model;
                model.getRoot(
                    function(root) {
                        model.getSimpleTree(
                            root, function(results) { alert(js2JSON(results)); }
                        );
                    }
                );
                node_editor.clear();  /* because otherwise this acts like a copy! */
            } else {
                alert("XXX [src] nodes length is " + nodes.length); /* XXX DEBUG */
            }
        }
    );
    progress_dialog.hide();
}

openils.Util.addOnLoad(init_test);
