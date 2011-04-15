dojo.require("dijit.Tree");
dojo.require("dijit.form.Button");
dojo.require("dojo.data.ItemFileWriteStore");
dojo.require("dojo.dnd.Source");
dojo.require("openils.vandelay.TreeDndSource");
dojo.require("openils.vandelay.TreeStoreModel");
dojo.require("openils.CGI");
dojo.require("openils.User");
dojo.require("openils.Util");
dojo.require("openils.PermaCrud");
dojo.require("openils.widget.ProgressDialog");

var localeStrings, node_editor, _crads, CGI, tree, match_set;

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
        dojo.create(
            "em", {"innerHTML": localeStrings.WORKING_MP_HERE},
            this.node_editor_container, "only"
        );
        this.dnd_source._ready = false;
    };

    this.is_sensible = function(mp) {
        var need_one = 0;
        ["tag", "svf", "bool_op"].forEach(
            function(field) { if (mp[field]()) need_one++; }
        );

        if (need_one != 1) {
            alert(localeStrings.POINT_NEEDS_ONE);
            return false;
        }

        if (mp.tag()) {
            if (
                !mp.tag().match(/^\d{3}$/) ||
                mp.subfield().length != 1 ||
                !mp.subfield().match(/\S/) ||
                mp.subfield().charCodeAt(0) < 32
            ) {
                alert(localeStrings.FAULTY_MARC);
                return false;
            }
        }

        return true;
    };

    this.build_vmsp = function() {
        var match_point = new vmsp();
        var controls = dojo.query("[fmfield]", this.node_editor_container);
        for (var i = 0; i < controls.length; i++) {
            var field = dojo.attr(controls[i], "fmfield");
            var value = _simple_value_getter(controls[i]);
            match_point[field](value);
        }

        if (!this.is_sensible(match_point)) return null;    /* will alert() */
        else return match_point;
    };

    this.update_draggable = function(draggable) {
        var mp;

        if (!(mp = this.build_vmsp())) return;  /* will alert() */

        draggable.match_point = mp;
        dojo.attr(draggable, "innerHTML", render_vmsp_label(mp));
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
                "type": "submit", "value": localeStrings.OK,
                "onclick": function() { self.update_draggable(draggable); }
            }, dojo.create(
                "td", {"colspan": 2, "align": "center"},
                dojo.create("tr", null, table)
            )
        );

        dojo.place(table, this.node_editor_container, "only");

        this.dnd_source.insertNodes(false, [draggable]);

        /* nice */
        try { dojo.query("select, input", table)[0].focus(); }
        catch(E) { console.log(String(E)); }

    };

    this._init.apply(this, arguments);
}

function render_vmsp_label(point, minimal) {
    /* quick and dirty */
    if (point.bool_op()) {
        return (openils.Util.isTrue(point.negate()) ? "N" : "") +
            point.bool_op();
    } else if (point.svf()) {
        return (openils.Util.isTrue(point.negate()) ? "NOT " : "") + (
            minimal ?  point.svf() :
                (point.svf() + " / " + _find_crad_by_name(point.svf()).label())
        );
    } else {
        return (openils.Util.isTrue(point.negate()) ? "NOT " : "") +
            point.tag() + " \u2021" + point.subfield();
    }
}

function replace_mode(explicit) {
    if (typeof explicit == "undefined")
        tree.model.replace_mode ^= 1;
    else
        tree.model.replace_mode = explicit;

    dojo.attr(
        "replacer", "innerHTML",
        localeStrings[
            (tree.model.replace_mode ? "EXIT" : "ENTER") + "_REPLACE_MODE"
        ]
    );
    dojo[tree.model.replace_mode ? "addClass" : "removeClass"](
        "replacer", "replace-mode"
    );
}

function delete_selected_in_tree() {
    /* relies on the fact that we only have one tree that would have
     * registered a dnd controller. */
    _tree_dnd_controllers[0].getSelectedItems().forEach(
        function(item) {
            if (item === tree.model.root)
                alert(localeStrings.LEAVE_ROOT_ALONE);
            else
                tree.model.store.deleteItem(item);
        }
    );
}

function new_match_set_tree() {
    var point = new vmsp();
    point.bool_op("AND");
    return [
        {
            "id": "root",
            "children": [],
            "name": render_vmsp_label(point),
            "match_point": point
        }
    ];
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
    var root = false;
    if (!refgen) {
        if (!point) {
            return new_match_set_tree();
        }
        refgen = 0;
        root = true;
    }

    var bathwater = point.children();
    point.children([]);
    var item = {
        "id": (root ? "root" : refgen),
        "name": render_vmsp_label(point),
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

function render_vms_metadata(match_set) {
    dojo.byId("vms-name").innerHTML = match_set.name();
    dojo.byId("vms-owner").innerHTML =
        aou.findOrgUnit(match_set.owner()).name();
    dojo.byId("vms-mtype").innerHTML = match_set.mtype();
}

function redraw_expression_preview() {
    tree.model.getRoot(
        function(root) {
            tree.model.get_simple_tree(
                root, function(r) {
                    dojo.attr(
                        "expr-preview",
                        "innerHTML",
                        render_expression_preview(r)
                    );
                }
            );
        }
    );
}

function render_expression_preview(r) {
    if (r.children().length) {
        return "(" + r.children().map(render_expression_preview).join(
            " " + render_vmsp_label(r) + " "
        ) + ")";
    } else if (!r.bool_op()) {
        return render_vmsp_label(r, true /* minimal */);
    } else {
        return "()";
    }
}

function save_tree() {
    progress_dialog.show(true);

    tree.model.getRoot(
        function(root) {
            tree.model.get_simple_tree(
                root, function(r) {
                    fieldmapper.standardRequest(
                        ["open-ils.vandelay",
                            "open-ils.vandelay.match_set.update"],/* XXX TODO */{
                            "params": [
                                openils.User.authtoken, match_set.id(), r
                            ],
                            "async": true,
                            "oncomplete": function(r) {
                                progress_dialog.hide();
                                /* catch exceptions */
                                r = openils.Util.readResponse(r);

                                location.href = location.href;
                            }
                        }
                    );
                }
            );
        }
    );
}
function my_init() {
    progress_dialog.show(true);

    dojo.requireLocalization("openils.vandelay", "match_set");
    localeStrings = dojo.i18n.getLocalization("openils.vandelay", "match_set");

    pcrud = new openils.PermaCrud();
    CGI = new openils.CGI();

    if (!CGI.param("match_set")) {
        alert(localeStrings.NO_CAN_DO);
        progress_dialog.hide();
        return;
    }

    render_vms_metadata(
        match_set = pcrud.retrieve("vms", CGI.param("match_set"))
    );

    /* No-one should have hundreds of these or anything, but theoretically
     * this could be problematic with a big enough list of crad objects. */
    _crads = pcrud.retrieveAll("crad", {"order_by": {"crad": "label"}});

    var match_set_tree = fieldmapper.standardRequest(
        ["open-ils.vandelay", "open-ils.vandelay.match_set.get_tree"],
        [openils.User.authtoken, CGI.param("match_set")]
    );

    var store = new dojo.data.ItemFileWriteStore({
        "data": {
            "identifier": "id",
            "label": "name",
            "items": dojoize_match_set_tree(match_set_tree)
        }
    });

    var tree_model = new openils.vandelay.TreeStoreModel({
        "store": store, "query": {"id": "root"}
    });

    var src = new dojo.dnd.Source("src-here");
    tree = new dijit.Tree(
        {
            "model": tree_model,
            "dndController": openils.vandelay.TreeDndSource,
            "dragThreshold": 8,
            "betweenThreshold": 5,
            "persist": false
        }, "tree-here"
    );

    node_editor = new NodeEditor(src, "node-editor-container");

    replace_mode(0);

    dojo.connect(
        src, "onDndDrop", null,
        function(source, nodes, copy, target) {
            /* Because of the... interesting... characteristics of DnD
             * design in dojo/dijit (at least as of 1.3), this callback will
             * fire both for our working node dndSource and for the tree!
             */
            if (source == this)
                node_editor.clear();  /* ... because otherwise this acts like a
                                         copy operation no matter what the user
                                         does, even though we really want a
                                         "move." */
        }
    );

    redraw_expression_preview();
    node_editor.clear();
    progress_dialog.hide();
}

openils.Util.addOnLoad(my_init);
