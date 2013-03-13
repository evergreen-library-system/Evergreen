dojo.require("dijit.form.Button");
dojo.require("dijit.form.RadioButton");
dojo.require("dijit.form.NumberSpinner");
dojo.require("dijit.form.TextBox");
dojo.require("dojo.dnd.Source");
dojo.require("openils.widget.AutoGrid");
dojo.require("openils.widget.ProgressDialog");
dojo.require("openils.PermaCrud");
dojo.require("openils.CGI");

var pcrud;
var dist_id;
var rlu_editor;
var cgi;
var context_url_param;

function format_routing_label(routing_label) {
    return routing_label ? routing_label : "[None]";
}

function load_sstr_grid() {
    sstr_grid.overrideEditWidgets.distribution =
        new dijit.form.TextBox({"disabled": true, "value": dist_id});

    sstr_grid.resetStore();
    sstr_grid.loadAll(
        {"order_by": {"ssub": "start_date DESC"}},
        {"distribution": dist_id}
    );
}

function load_sdist_display() {
    pcrud.retrieve(
        "sdist", dist_id, {
            "onresponse": function(r) {
                if (r = openils.Util.readResponse(r)) {
                    var link = dojo.byId("sdist_label_here");
                    link.onclick = function() {
                        location.href = oilsBasePath +
                            "/serial/subscription?id=" +
                            r.subscription() + "&tab=distributions" +
                            context_url_param;
                    }
                    link.innerHTML = r.label();
                    load_sdist_org_unit_display(r);
                }
            }
        }
    );
}

function load_sdist_org_unit_display(dist) {
    dojo.byId("sdist_org_unit_name_here").innerHTML =
        aou.findOrgUnit(dist.holding_lib()).name();
}

function create_many_streams(fields) {
    var streams = [];
    for (var i = 0; i < fields.quantity; i++) {
        var stream = new sstr();
        stream.distribution(dist_id);
        streams.push(stream);
    }

    progress_dialog.show(true);
    this.pcrud.create(
        streams, {
            "oncomplete": function(r, list) {
                progress_dialog.hide();
                sstr_grid.refresh();
            },
            "onerror": function(r) {
                progress_dialog.hide();
                alert("Error creating streams!"); /* XXX i18n */
            }
        }
    );
}

function RLUEditor() {
    var self = this;

    function _reader_xor_dept_toggle(value) {
        var reader = dijit.byId("reader");
        var department = dijit.byId("department");

        if (this.id.match(/\w+$/).pop() == "reader")
            _reader_toggle(value, reader, department);
        else
            _department_toggle(value, reader, department);
    }

    function _reader_toggle(value, reader, department) {
        if (value) {
            reader.attr("disabled", false);
            department.attr("disabled", true);
            setTimeout(function() { reader.focus(); }, 125);
        }
    }

    function _department_toggle(value, reader, department) {
        if (value) {
            reader.attr("disabled", true);
            department.attr("disabled", false);
            setTimeout(function() { department.focus(); }, 125);
        }
    }

    this.user_to_source_entry = function(user) {
        var node = dojo.create("li");
        var s;
        if (user.reader()) {
            s = dojo.string.substitute(
                this.template.reader, [
                    user.reader().card().barcode(),
                    user.reader().family_name(),
                    user.reader().first_given_name(),
                    user.reader().second_given_name(),
                    user.reader().home_ou().shortname()
                ].map(function(o) { return o == null ? "" : o; })
            );
        } else {
            s = dojo.string.substitute(
                this.template.department, [user.department()]
            );
        }

        if (user.note()) {
            s += dojo.string.substitute(this.template.note, [user.note()]);
        }

        node.innerHTML = "&nbsp;" + s;

        dojo.create(
            "a", {
                "href": "javascript:void(0);",
                "onclick": function() { self.toggle_deleted(node); },
                "innerHTML": this.template.remove
            }, node, "first"
        );

        node._user = user;
        return node;
    };

    this.toggle_deleted = function(node) {
        if (node._user.isdeleted()) {
            dojo.style(node, "textDecoration", "none");
            node._user.isdeleted(false);
        } else {
            dojo.style(node, "textDecoration", "line-through");
            node._user.isdeleted(true);
        }
    };

    this.new_user = function() {
        var form = this.dialog.attr("value");
        var user = new fieldmapper.srlu();
        user.isnew(true);
        user.stream(this.stream);

        if (form.note)
            user.note(form.note);

        if (form.department) {
            user.department(form.department);
        } else if (form.reader) {
            this.add_button.attr("disabled", true);
            fieldmapper.standardRequest(
                ["open-ils.actor",
                    "open-ils.actor.user.fleshed.retrieve_by_barcode"], {
                    "params": [openils.User.authtoken, form.reader, true],
                    "timeout": 10, /* sync */
                    "onresponse": function(r) {
                        if (r = openils.Util.readResponse(r)) {
                            user.reader(r);
                        }
                    }
                }
            );
            this.add_button.attr("disabled", false);
        } else {
            alert("Provide either a reader or a department."); /* XXX i18n */
            return;
        }

        ["reader", "department", "note"].forEach(
            function(s) { dijit.byId(s).attr("value", ""); }
        );

        this.source.insertNodes(false, [self.user_to_source_entry(user)]);
    }

    this.show = function() {
        if (sstr_grid.getSelectedRows().length != 1) {
            alert(
                "Use the checkboxes to select exactly one stream " +
                "for this operation."   /* XXX i18n */
            );
        } else {
            /* AutoGrid.getSelectedItems() yields a weird, non-FM object */
            this.stream = sstr_grid.getSelectedItems()[0].id[0];

            this.source.selectAll();
            this.source.deleteSelectedNodes();
            this.source.clearItems();

            this.dialog.show();

            fieldmapper.standardRequest(
                ["open-ils.serial",
                    "open-ils.serial.routing_list_users.fleshed_and_ordered"], {
                    "params": [openils.User.authtoken, this.stream],
                    "async": true,
                    "onresponse": function(r) {
                        if (r = openils.Util.readResponse(r)) {
                            self.source.insertNodes(
                                false, [self.user_to_source_entry(r)]
                            );
                        }
                    },
                    "oncomplete": function() {
                        setTimeout(
                            function() { self.save_button.focus(); }, 125
                        );
                    }
                }
            );
        }
    };

    this.save = function() {
        var obj_list = this.source.getAllNodes().map(
            function(node) {
                var obj = node._user;
                if (obj.reader())
                    obj.reader(obj.reader().id());

                return obj;
            }
        );

        this.save_button.attr("disabled", true);

        /* pcrud.apply *almost* could have handled this, but there's a reason
         * it doesn't, and it has to do with the unique key constraint on the
         * pos field in srlu objects.
         */
        try {
            fieldmapper.standardRequest(
                /* This method will set pos in ascending order. */
                ["open-ils.serial",
                    "open-ils.serial.routing_list_users.replace"], {
                    "params": [openils.User.authtoken, obj_list],
                    "timeout": 10, /* sync */
                    "oncomplete": function(r) {
                        openils.Util.readResponse(r);   /* display exceptions */
                    }
                }
            );
        } catch (E) {
            alert(E); /* XXX i18n */
        }

        this.save_button.attr("disabled", false);
    };

    this._init = function(dialog) {
        this.dialog = dijit.byId("routing_list_dialog");
        this.source = routing_list_source;

        this.template = {};
        ["reader", "department", "note", "remove"].forEach(
            function(n) {
                self.template[n] =
                    dojo.byId("routing_list_user_template_" + n).innerHTML;
            }
        );

        this.add_button = dijit.byId("routing_list_add_button");
        this.save_button = dijit.byId("routing_list_save_button");

        dijit.byId("reader_xor_dept-reader").onChange =
            _reader_xor_dept_toggle;
        dijit.byId("reader_xor_dept-department").onChange =
            _reader_xor_dept_toggle;
    };

    this._init.apply(this, arguments);
}

openils.Util.addOnLoad(
    function() {
        cgi = new openils.CGI();
        pcrud = new openils.PermaCrud();
        rlu_editor = new RLUEditor();

        dist_id = cgi.param("distribution");
        load_sdist_display();
        load_sstr_grid();

        var context = cgi.param('context');
        if (context) {
            context_url_param = '&context=' + context;
        } else {
            context_url_param = '';
        }
    }
);
