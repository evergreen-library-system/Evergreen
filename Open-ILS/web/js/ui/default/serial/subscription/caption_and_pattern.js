function SCAPRow() {
    var self = this;
    var _fields = ["id", "type", "pattern_code", "active", "create_date"];

    this.init = function(id, manager, datum) {
        this.id = id;
        this.manager = manager;
        this.element = dojo.clone(manager.template);

        /* find the controls for each field */
        this.controls = {};
        _fields.forEach(
            function(k) {
                self.controls[k] = dojo.query(
                    "[name='" + k + "'] [control]", self.element
                )[0];
            }
        );

        /* set up the remover button */
        this.remover = dojo.query("[name='remover'] button", this.element)[0];
        this.remover.onclick = function() { manager.remove_row(self); };

        this.save_button = dojo.query("[name='save'] button", this.element)[0];
        this.save_button.onclick = function() { manager.save_row(self); };

        this.wizard_button = dojo.query(
            "[name='pattern_code'] button", this.element
        )[0];
        this.wizard_button.onclick = function() {
            if (
                openils.Util.trimString(
                    self.controls.pattern_code.value
                ).length &&
                !confirm(
                    "Are you sure you want to erase this pattern code\n" +
                    "and create a new one via the Wizard?"  /* XXX i18n */
                )
            ) {
                return;
            }
            try {
                window.openDialog(
                    xulG.url_prefix("XUL_SERIAL_PATTERN_WIZARD"),
                    "pattern_wizard",
                    "width=800,height=400",
                    function(value) {
                        self.controls.pattern_code.value = value;
                        self.controls.pattern_code.onchange();
                    }
                );
            } catch (E) {
                alert(E); /* XXX */
            }
        };

        /* set up onchange handlers for control fields */
        this.controls.type.onchange = function() {
            self.has_changed(true);
            self.datum.type(this.getValue());
        };
        this.controls.pattern_code.onchange = function() {
            self.has_changed(true);
            self.datum.pattern_code(this.value);
        };
        this.controls.active.onchange = function() {
            self.has_changed(true);
            self.datum.active(this.checked ? "t" : "f");
        };

        this.load_fm_object(datum);
    };

    this.load_fm_object = function(datum) {
        if (typeof datum != "undefined") {
            this.datum = datum;

            this.controls.type.setValue(datum.type());
            this.controls.pattern_code.value = datum.pattern_code();
            this.controls.active.checked = openils.Util.isTrue(datum.active());
            this.controls.id.innerHTML = datum.id() || "";
            this.controls.create_date.innerHTML =
                openils.Util.timeStamp(datum.create_date());

            /* Once created, scap objects' pattern_code field is meant to
             * be immutable.
             *
             * See http://list.georgialibraries.org/pipermail/open-ils-dev/2010-May/006079.html
             *
             * The DB trigger mentioned was never created to enforce this
             * immutability at that level, but this should keep users from
             * doing the wrong thing by mistake.
             */
            this.controls.pattern_code.readOnly = true;
            this.wizard_button.disabled = true;

            this.has_changed(false);
        } else {
            this.datum = new scap();
            this.datum.subscription(this.manager.sub_id);

            _fields.forEach(
                function(k) {
                    try { self.controls[k].onchange(); } catch (E) { ; }
                }
            );
        }
    };

    this.has_changed = function(has) {
        if (typeof has != "undefined") {
            this._has_changed = has;
            this.save_button.disabled = !has;
            dojo.attr(this.element, "changed", String(has));
        }

        return this._has_changed;
    };

    this.init.apply(this, arguments);
}

function SCAPEditor() {
    var self = this;

    this.init = function(sub_id, pcrud) {
        this.sub_id = sub_id;
        this.pcrud = pcrud || new openils.PermaCrud();

        this.setup();
        this.reset();
        this.load_existing();
    };

    this.reset = function() {
        this.virtRowCount = 0;
        this.rows = {};

        dojo.empty(this.body);
    };

    this.setup = function() {
        var template = dojo.query("#scap_editor tbody tr")[0];
        this.body = template.parentNode;
        this.template = this.body.removeChild(template);

        dojo.query("#scap_editor button[name='add']")[0].onclick =
            function() { self.add_row(); };

        openils.Util.show("scap_editor");
    };

    this.load_existing = function() {
        this.pcrud.search("scap", {
                "subscription": this.sub_id
            }, {
                "order_by": {"scap": "create_date"},
                "onresponse": function(r) {
                    if (r = openils.Util.readResponse(r)) {
                        r.forEach(function(datum) { self.add_row(datum); });
                    }
                }
            }
        );
    };

    this.add_row = function(datum) {
        var id;
        if (typeof datum == "undefined") {
            id = --(this.virtRowCount);
            this.rows[id] = new SCAPRow(id, this);
        } else {
            id = datum.id();
            this.rows[id] = new SCAPRow(id, this, datum);
        }

        dojo.place(this.rows[id].element, this.body, "last");
    };

    this.save_row = function(row) {
        var old_id = row.id;
        if (old_id < 0) {
            this.pcrud.create(
                row.datum, {
                    "oncomplete": function(r, list) {
                        openils.Util.readResponse(r);
                        var new_id = list[0].id();
                        row.id = new_id;
                        delete self.rows[old_id];
                        self.rows[new_id] = row;
                        row.load_fm_object(list[0]);
                        row.has_changed(false);
                    }
                }
            );
        } else {
            this.pcrud.update(
                row.datum, {
                    "oncomplete": function(r, list) {
                        openils.Util.readResponse(r);
                        row.has_changed(false);
                    }
                }
            );
        }
    };

    this.remove_row = function(row) {
        function _remove(row) {
            dojo.destroy(self.rows[row.id].element);
            delete self.rows[row.id];
        }

        if (row.id < 0) { /* virtual row */
            _remove(row);
        } else { /* real row */
            this.pcrud.eliminate(
                row.datum, {
                    "oncomplete": function(r, list) {
                        openils.Util.readResponse(r);
                        _remove(row);
                    }
                }
            );
        }
    };

    this.init.apply(this, arguments);
}

function SCAPImporter() {
    var self = this;

    this.init = function(sub) {
        this.sub = sub;

        this.template = dojo.byId("record_template");
        this.template = this.template.parentNode.removeChild(this.template);
        this.template.removeAttribute("id");

        dojo.byId("scaps_from_bib").onclick = function() { self.launch(); };
    };

    this.launch = function() {
        this.reset();
        progress_dialog.show(true);

        fieldmapper.standardRequest(
            ["open-ils.serial",
                "open-ils.serial.caption_and_pattern.find_legacy_by_bib_record"], {
                "params": [openils.User.authtoken, this.sub.record_entry()],
                "timeout": 10, /* sync */
                "onresponse": function(r) {
                    if (r = openils.Util.readResponse(r)) {
                        self.add_record(r);
                    }
                }
            }
        );

        progress_dialog.hide();
        if (this.any_records())
            scaps_from_bib_dialog.show();
        else /* XXX i18n */
            alert("No related records with any caption and pattern fields.");
    };

    this.reset = function() {
        dojo.empty("record_holder");
        this._records = [];
    };

    this.any_records = function() {
        return Boolean(this._records.length);
    }

    this.add_record = function(obj) {
        var row = dojo.clone(this.template);

        var checkbox = dojo.query("input[type='checkbox']", row)[0];
        obj._checkbox = checkbox;

        this._records.push(obj);

        if (obj.classname == "bre") {
            /* XXX i18n */
            node_by_name("obj_class", row).innerHTML = "Bibliographic";
            node_by_name("obj_id", row).innerHTML = obj.tcn_value();
            if (obj.owner()) {
                openils.Util.show(
                    node_by_name("obj_owner_container", row), "inline"
                );
                node_by_name("obj_owner", row).innerHTML = obj.owner();
            }
        } else {
            /* XXX i18n */
            node_by_name("obj_class", row).innerHTML = "Legacy serial";
            node_by_name("obj_id", row).innerHTML = obj.id();
            node_by_name("obj_owner", row).innerHTML = obj.owning_lib();
            openils.Util.show(
                node_by_name("obj_owner_container", row), "inline"
            );
        }

        if (!openils.Util.isTrue(obj.active()))
            openils.Util.show(node_by_name("obj_inactive", row), "inline");

        node_by_name("obj_create", row).innerHTML =
            /* XXX i18n */
            dojo.string.substitute(
                "${0}, ${1} ${2}", [
                    obj.creator().family_name(),
                    obj.creator().first_given_name(),
                    obj.creator().second_given_name(),
                ].map(function(o) { return o || ""; })
            ) + " on " + openils.Util.timeStamp(obj.create_date());

        node_by_name("obj_edit", row).innerHTML =
            /* XXX i18n */
            dojo.string.substitute(
                "${0}, ${1} ${2}", [
                    obj.editor().family_name(),
                    obj.editor().first_given_name(),
                    obj.editor().second_given_name(),
                ].map(function(o) { return o || ""; })
            ) + " on " + openils.Util.timeStamp(obj.edit_date());

        dojo.place(row, "record_holder", "last");
    };

    this.import = function() {
        var documents = this._records.filter(
            function(o) { return o._checkbox.checked; }
        ).map(
            function(o) { return o.marc(); }
        );

        if (!documents.length) {
            /* XXX i18n */
            alert("You have selected no records from which to import.");
        } else {
            progress_dialog.show(true);
            fieldmapper.standardRequest(
                ["open-ils.serial",
                    "open-ils.serial.caption_and_pattern.create_from_records"],{
                    "params": [openils.User.authtoken,this.sub.id(),documents],
                    "async": false,
                    "onresponse": function(r) {
                        if (r = openils.Util.readResponse(r)) {
                            cap_editor.add_row(r);
                        }
                    }
                }
            );
            progress_dialog.hide();
        }
    };

    this.init.apply(this, arguments);
}
