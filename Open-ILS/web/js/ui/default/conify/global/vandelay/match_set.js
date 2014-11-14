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
dojo.require("openils.widget.AutoGrid");

var localeStrings, node_editor, qnode_editor, _crads, CGI, tree, match_set;

var NodeEditorAbstract = {
    "_svf_select_template": null,
    "_simple_value_getter": function(control) {
        if (typeof control.selectedIndex != "undefined")
            return control.options[control.selectedIndex].value;
        else if (dojo.attr(control, "type") == "checkbox")
            return control.checked;
        else
            return control.value;
    },
    "is_sensible": function(thing) {
        var need_one = 0;
        this.foi.forEach(function(field) { if (thing[field]()) need_one++; });

        if (need_one != 1) {
            alert(localeStrings.POINT_NEEDS_ONE);
            return false;
        }

        if (thing.tag()) {
            if (
                !thing.tag().match(/^\d{3}$/) ||
                thing.subfield().length != 1 ||
                !thing.subfield().match(/\S/) ||
                thing.subfield().charCodeAt(0) < 32
            ) {
                alert(localeStrings.FAULTY_MARC);
                return false;
            }
        }

        return true;
    },
    "_add_consistent_controls": function(tgt) {
        if (!this._consistent_controls) {
            var trs = dojo.query(this._consistent_controls_query);
            this._consistent_controls = [];
            for (var i = 0; i < trs.length; i++)
                this._consistent_controls[i] = dojo.clone(trs[i]);
        }

        this._consistent_controls.forEach(
            function(node) { dojo.place(dojo.clone(node), tgt); }
        );
    },
    "_factories_by_type": {
        "svf": function() {
            if (!self._svf_select_template) {
                self._svf_select_template = dojo.create(
                    "select", {"fmfield": "svf"}
                );
                for (var i=0; i<_crads.length; i++) {
                    dojo.create(
                        "option", {
                            "value": _crads[i].name(),
                            "innerHTML": _crads[i].label()
                        }, self._svf_select_template
                    );
                }
            }

            var select = dojo.clone(self._svf_select_template);
            dojo.attr(select, "id", "svf-select");
            var label = dojo.create(
                "label", {
                    "for": "svf-select", "innerHTML": localeStrings.SVF + ":"
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
        "heading" : function() {
            var tr = dojo.create("tr");
            dojo.create(
                "label", {
                    "for": "heading-input", 
                    "innerHTML": localeStrings.HEADING_MATCH
                }, dojo.create("td", null, tr)
            );

            dojo.create(
                "input", {
                    "id": "heading-input",
                    "type": "checkbox",
                    "checked": true,
                    "disabled": true, // if you don't want it, don't use it.
                    "fmfield": "heading"
                }, dojo.create("td", null, tr)
            );

            return [tr];
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
    }
};

function apply_base_class(cls, basecls) {
    openils.Util.objectProperties(basecls).forEach(
        function(m) { cls[m] = basecls[m]; }
    );
}

function QualityNodeEditor() {
    var self = this;
    this.foi = ["tag", "svf"]; /* Fields of Interest - starting points for UI */

    this._init = function(qnode_editor_container) {
        this._consistent_controls_query =
            "[consistent-controls], [quality-controls]";
        this.qnode_editor_container = dojo.byId(qnode_editor_container);
        this.clear();
    };

    this.clear = function() {
        dojo.create(
            "em", {"innerHTML": localeStrings.WORKING_QM_HERE},
            this.qnode_editor_container, "only"
        );
    };

    this.build_vmsq = function() {
        var metric = new vmsq();
        metric.match_set(match_set.id());   /* using global */
        var controls = dojo.query("[fmfield]", this.qnode_editor_container);
        for (var i = 0; i < controls.length; i++) {
            var field = dojo.attr(controls[i], "fmfield");
            var value = this._simple_value_getter(controls[i]);
            metric[field](value);
        }

        if (!this.is_sensible(metric)) return null;    /* will alert() */
        else return metric;
    };

    this.add = function(type) {
        this.clear();

        /* these are the editing widgets */
        var table = dojo.create("table", {"className": "node-editor"});

        var nodes = this._factories_by_type[type]();
        for (var i = 0; i < nodes.length; i++) dojo.place(nodes[i], table);

        this._add_consistent_controls(table);

        var ok_cxl_td = dojo.create(
            "td", {"colspan": 2, "align": "center", "className": "space-me"},
            dojo.create("tr", null, table)
        );

        dojo.create(
            "input", {
                "type": "submit", "value": localeStrings.OK,
                "onclick": function() {
                    var metric = self.build_vmsq();
                    if (metric) {
                        self.clear();
                        pcrud.create(
                            metric, {
                                /* borrowed from openils.widget.AutoGrid */
                                "oncomplete": function(req, cudResults) {
                                    var fmObject = cudResults[0];
                                    if (vmsq_grid.onPostCreate)
                                        vmsq_grid.onPostCreate(fmObject);
                                    if (fmObject) {
                                        vmsq_grid.store.newItem(
                                            fmObject.toStoreItem()
                                        );
                                    }
                                    setTimeout(function() {
                                        try {
                                            vmsq_grid.selection.select(vmsq_grid.rowCount-1);
                                            vmsq_grid.views.views[0].getCellNode(vmsq_grid.rowCount-1, 1).focus();
                                        } catch (E) {}
                                    },200);
                                }
                            }
                        );
                    }
                }
            }, ok_cxl_td
        );
        dojo.create(
            "input", {
                "type": "reset", "value": localeStrings.CANCEL,
                "onclick": function() { self.clear(); }
            }, ok_cxl_td
        );

        dojo.place(table, this.qnode_editor_container, "only");

        /* nice */
        try { dojo.query("select, input", table)[0].focus(); }
        catch(E) { console.log(String(E)); }

    };

    apply_base_class(self, NodeEditorAbstract);
    this._init.apply(this, arguments);
}

function NodeEditor() {
    var self = this;
    this.foi = ["tag", "svf", "heading", "bool_op"]; /* Fields of Interest - starting points for UI */

    this._init = function(dnd_source, node_editor_container) {
        this._consistent_controls_query =
            "[consistent-controls], [point-controls]";
        this.dnd_source = dnd_source;
        this.node_editor_container = dojo.byId(node_editor_container);

        // hide match point types which are not relevent to
        // the current record type
        if (match_set.mtype() == 'authority') {
            openils.Util.hide('record-attr-btn');
        } else {
            openils.Util.hide('heading-match-btn');
        }
    };

    this.clear = function() {
        this.dnd_source.selectAll().deleteSelectedNodes();
        dojo.create(
            "em", {"innerHTML": localeStrings.WORKING_MP_HERE},
            this.node_editor_container, "only"
        );
        this.dnd_source._ready = false;
    };

    this.build_vmsp = function() {
        var match_point = new vmsp();
        var controls = dojo.query("[fmfield]", this.node_editor_container);
        for (var i = 0; i < controls.length; i++) {
            var field = dojo.attr(controls[i], "fmfield");
            var value = this._simple_value_getter(controls[i]);
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

    this.add = function(type) {
        this.clear();

        /* a representation, not the editing widgets, but will also carry
         * the fieldmapper object when dragged to the tree */
        var draggable = dojo.create(
            "li", {"innerHTML": localeStrings.DEFINE_MP}
        );

        /* these are the editing widgets */
        var table = dojo.create("table", {"className": "node-editor"});

        var nodes = this._factories_by_type[type]();
        for (var i = 0; i < nodes.length; i++) dojo.place(nodes[i], table);

        if (type != "bool_op")
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

    apply_base_class(self, NodeEditorAbstract);

    this._init.apply(this, arguments);
}

function find_crad_by_name(name) {
    for (var i = 0; i < _crads.length; i++) {
        if (_crads[i].name() == name)
            return _crads[i];
    }
    return null;
}

function render_vmsp_label(point, minimal) {
    /* "minimal" has these implications:
     * for svf, only show the code, not the longer label.
     * no quality display
     */
    if (point.bool_op()) {
        return point.bool_op();
    } else if (point.svf()) {
        return (openils.Util.isTrue(point.negate()) ? "NOT " : "") + (
            minimal ?  point.svf() :
                (point.svf() + " / " + find_crad_by_name(point.svf()).label()) +
                " | " + dojo.string.substitute(
                    localeStrings.MATCH_SCORE, [point.quality()]
                )
        );
    } else if (point.heading() === true || point.heading() == 't') {
        return localeStrings.HEADING_MATCH +
            " | " + dojo.string.substitute(
                localeStrings.MATCH_SCORE, [point.quality()]);
    } else {
        return (openils.Util.isTrue(point.negate()) ? "NOT " : "") +
            point.tag() + " \u2021" + point.subfield() + (minimal ? "" : " | " +
                dojo.string.substitute(
                    localeStrings.MATCH_SCORE, [point.quality()]
                )
            );
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
function dojoize_match_set_tree(point, depth) {
    var root = false;
    if (!depth) {
        if (!point) {
            return new_match_set_tree();
        }
        depth = 0;
        root = true;
    }

    var bathwater = point.children();
    point.children([]);
    var item = {
        "id": (root ? "root" : point.id()),
        "name": render_vmsp_label(point),
        "match_point": point.clone(),
        "children": []
    };
    point.children(bathwater);

    var results = [item];

    if (point.children()) {
        for (var i = 0; i < point.children().length; i++) {
            var child = point.children()[i];
            item.children.push({"_reference": child.id()});
            results = results.concat(
                dojoize_match_set_tree(child, ++depth)
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
                            "open-ils.vandelay.match_set.update"], {
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

function init_vmsq_grid() {
    vmsq_grid.loadAll(
        {"order_by": {"vmsq": "quality"}},
        {"match_set": match_set.id()}
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
    _crads = match_set.mtype() == 'authority' ? [] :
        pcrud.retrieveAll("crad", {"order_by": {"crad": "label"}});

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
    qnode_editor = new QualityNodeEditor("qnode-editor-container");

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

    init_vmsq_grid();

    progress_dialog.hide();
}

openils.Util.addOnLoad(my_init);
