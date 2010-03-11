dojo.require('dijit.layout.ContentPane');
dojo.require('openils.User');
dojo.require('openils.Util');
dojo.require('openils.PermaCrud');

var PO = null;
var liTable;
var poNoteTable;

function AcqPoNoteTable() {
    var self = this;

    this.notesTbody = dojo.byId("acq-po-notes-tbody");
    this.notesRow = this.notesTbody.removeChild(dojo.byId("acq-po-notes-row"));

    dojo.byId("acq-po-notes-back-button").onclick = function() { self.hide(); };
    dojo.byId("acq-po-view-notes").onclick = function() { self.show(); };

    /* widgets' event properties are cased likeThis */
    acqPoCreateNoteSubmit.onClick = function() {
        if (!acqPoCreateNoteText.attr("value")) return;

        /* prep new note */
        var note = new acqpon();
        note.vendor_public(
            Boolean(acqPoCreateNoteVendorPublic.attr('checked'))
        );
        note.value(acqPoCreateNoteText.attr("value"));
        note.purchase_order(PO.id());
        note.isnew(true);

        /* save it */
        self.updatePoNotes(note);

        /* reset fields for next use */
        acqPoCreateNoteText.attr("value", "");
        acqPoCreateNoteVendorPublic.attr("checked", false);
    };

    this.drawPoNote = function(note) {
        if (note.isdeleted())
            return;

        var row = dojo.clone(this.notesRow);

        nodeByName("value", row).innerHTML = note.value();

        if (note.vendor_public() == "t")
            nodeByName("vendor_public", row).innerHTML =
                localeStrings.VENDOR_PUBLIC;

        nodeByName("delete", row).onclick = function() {
            note.isdeleted(true);
            self.notesTbody.removeChild(row);
            self.updatePoNotes();
        };

        if (note.edit_time()) {
            nodeByName("edit_time", row).innerHTML =
                dojo.date.locale.format(
                    dojo.date.stamp.fromISOString(note.edit_time()),
                    {"formatLength": "short"}
                );
        }

        self.notesTbody.appendChild(row);
    };

    this.drawPoNotes = function() {
        /* sort */
        PO.notes(
            PO.notes().sort(
                function(a, b) {
                    return (a.edit_time() < b.edit_time()) ? 1 : -1;
                }
            )
        );

        /* remove old renderings of notes */
        dojo.empty(this.notesTbody);

        PO.notes().forEach(function(o) { self.drawPoNote(o); });
    };

    this.updatePoNotesCount = function() {
        dojo.byId("acq-po-view-notes").innerHTML = PO.notes().length;
    };

    this.updatePoNotes = function(newNote) {
        var notes = newNote ?
            [newNote] :
            PO.notes().filter(
                function(o) {
                    if (o.ischanged() || o.isnew() || o.isdeleted())
                        return o;
                }
            );

        if (notes.length < 1)
            return;

        progressDialog.show();

        fieldmapper.standardRequest(
            ["open-ils.acq", "open-ils.acq.po_note.cud.batch"], {
                "async": true,
                "params": [openils.User.authtoken, notes],
                "onresponse": function(r) {
                    var resp = openils.Util.readResponse(r);
                    if (resp) {
                        progressDialog.update(resp);

                        if (!resp.note.isdeleted()) {
                            resp.note.isnew(false);
                            resp.note.ischanged(false);
                            PO.notes().push(resp.note);
                        }
                    }
                },
                "oncomplete": function() {
                    if (!newNote) {
                        /* remove the old changed notes */
                        var list = [];
                        PO.notes(
                            PO.notes().filter(
                                function(o) {
                                    return (!(
                                        o.ischanged() || o.isnew() ||
                                        o.isdeleted()
                                    ));
                                }
                            )
                        );
                    }

                    progressDialog.hide();
                    self.updatePoNotesCount();
                    self.drawPoNotes();
                }
            }
        );
    };

    this.hide = function() {
        openils.Util.hide("acq-po-notes-div");
        liTable.show("list");
    };

    this.show = function() {
        liTable.hide();
        self.drawPoNotes();
        openils.Util.show("acq-po-notes-div");
    };
}

function updatePoState(po_info) {
    var data = po_info[PO.id()];
    if (data) {
        for (var key in data)
            PO[key](data[key]);
        renderPo();
    }
}

function renderPo() {
    dojo.byId("acq-po-view-id").innerHTML = PO.id();
    dojo.byId("acq-po-view-name").innerHTML = PO.name();
    dojo.byId("acq-po-view-total-li").innerHTML = PO.lineitem_count();
    dojo.byId("acq-po-view-total-enc").innerHTML = PO.amount_encumbered();
    dojo.byId("acq-po-view-total-spent").innerHTML = PO.amount_spent();
    dojo.byId("acq-po-view-state").innerHTML = PO.state(); // TODO i18n
    dojo.byId("acq-po-view-notes").innerHTML = PO.notes().length;

    if(PO.state() == "pending") {
        openils.Util.show("acq-po-activate");
        if (PO.lineitem_count() > 1)
            openils.Util.show("acq-po-split");
    }
}


function init() {
    /* set up li table */
    liTable = new AcqLiTable();
    liTable.reset();
    liTable.isPO = poId;
    liTable.poUpdateCallback = updatePoState;

    /* set up po notes table */
    poNoteTable = new AcqPoNoteTable();

    /* retrieve data and populate */
    fieldmapper.standardRequest(
        ['open-ils.acq', 'open-ils.acq.purchase_order.retrieve'],
        {   async: true,
            params: [openils.User.authtoken, poId, {
                "flesh_price_summary": true,
                "flesh_lineitem_count": true,
                "flesh_notes": true
            }],
            oncomplete: function(r) {
                PO = openils.Util.readResponse(r); /* save PO globally */
                renderPo();
            }
        }
    );

    fieldmapper.standardRequest(
        ['open-ils.acq', 'open-ils.acq.lineitem.search'],
        {   async: true,
            params: [openils.User.authtoken, {purchase_order:poId}, {flesh_attrs:true, flesh_notes:true}],
            onresponse: function(r) {
                liTable.show('list');
                liTable.addLineitem(openils.Util.readResponse(r));
            }
        }
    );
}

function activatePo() {
    progressDialog.show(true);
    try {
        fieldmapper.standardRequest(
            ['open-ils.acq', 'open-ils.acq.purchase_order.activate'],
            {   async: true,
                params: [openils.User.authtoken, PO.id()],
                oncomplete : function() {
                    location.href = location.href;
                }
            }
        );
    } catch(E) {
        progressDialog.hide();
    }
}

function splitPo() {
    progressDialog.show(true);
    try {
        var list;
        fieldmapper.standardRequest(
            ['open-ils.acq', 'open-ils.acq.purchase_order.split_by_lineitems'],
            {   async: true,
                params: [openils.User.authtoken, PO.id()],
                onresponse : function(r) {
                    list = openils.Util.readResponse(r);
                },
                oncomplete : function() {
                    progressDialog.hide();
                    if (list) {
                        location.href = oilsBasePath + '/eg/acq/po/search/' +
                            list.join(",");
                    }
                }
            }
        );
    } catch(E) {
        progressDialog.hide();
        alert(E);
    }
}

function updatePoName() {
    var value = prompt('Enter new purchase order name:', PO.name()); // TODO i18n
    if(!value || value == PO.name()) return;
    PO.name(value);
    var pcrud = new openils.PermaCrud();
    pcrud.update(PO, {
        oncomplete : function(r, cudResults) {
            var stat = cudResults[0];
            if(stat)
                dojo.byId('acq-po-view-name').innerHTML = value;
        }
    });
}

openils.Util.addOnLoad(init);
