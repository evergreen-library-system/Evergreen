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
            try {
                netscape.security.PrivilegeManager.enablePrivilege(
                    "UniversalXPConnect"
                );
                window.openDialog(
                    xulG.url_prefix("/xul/server/serial/pattern_wizard.xul"),
                    "pattern_wizard",
                    "scrollbars=yes", /* XXX doesn't work this way? */
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
