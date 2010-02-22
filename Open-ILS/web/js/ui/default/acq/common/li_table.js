dojo.require('dojo.date.locale');
dojo.require('dojo.date.stamp');
dojo.require('dijit.form.Button');
dojo.require('dijit.form.TextBox');
dojo.require('dijit.form.FilteringSelect');
dojo.require('dijit.form.Textarea');
dojo.require('dijit.ProgressBar');
dojo.require('openils.User');
dojo.require('openils.Util');
dojo.require('openils.acq.Lineitem');
dojo.require('openils.acq.PO');
dojo.require('openils.acq.Picklist');
dojo.require('openils.widget.AutoFieldWidget');
dojo.require('dojo.data.ItemFileReadStore');
dojo.require('openils.widget.ProgressDialog');
dojo.require('openils.PermaCrud');
dojo.require('openils.XUL');

dojo.requireLocalization('openils.acq', 'acq');
var localeStrings = dojo.i18n.getLocalization('openils.acq', 'acq');
const XUL_OPAC_WRAPPER = 'chrome://open_ils_staff_client/content/cat/opac.xul';
var li_exportable_attrs = ["issn", "isbn", "upc"];

function nodeByName(name, context) {
    return dojo.query('[name='+name+']', context)[0];
}


var liDetailBatchFields = ['fund', 'owning_lib', 'location', 'collection_code', 'circ_modifier', 'cn_label'];
var liDetailFields = liDetailBatchFields.concat(['barcode', 'note']);

function AcqLiTable() {

    var self = this;
    this.liCache = {};
    this.plCache = {};
    this.poCache = {};
    this.dfaCache = {};
    this.dfeOffset = 0;
    this.toggleState = false;
    this.tbody = dojo.byId('acq-lit-tbody');
    this.selectors = [];
    this.noteAcks = {};
    this.authtoken = openils.User.authtoken;
    this.rowTemplate = this.tbody.removeChild(dojo.byId('acq-lit-row'));
    this.copyTbody = dojo.byId('acq-lit-li-details-tbody');
    this.copyRow = this.copyTbody.removeChild(dojo.byId('acq-lit-li-details-row'));
    this.copyBatchRow = dojo.byId('acq-lit-li-details-batch-row');
    this.copyBatchWidgets = {};
    this.liNotesTbody = dojo.byId('acq-lit-notes-tbody');
    this.liNotesRow = this.liNotesTbody.removeChild(dojo.byId('acq-lit-notes-row'));
    this.realCopiesTbody = dojo.byId('acq-lit-real-copies-tbody');
    this.realCopiesRow = this.realCopiesTbody.removeChild(dojo.byId('acq-lit-real-copies-row'));
    this._copy_fields_for_acqdf = ['owning_lib', 'location'];

    dojo.connect(acqLitLiActionsSelector, 'onChange', 
        function() { 
            self.applySelectedLiAction(this.attr('value')) 
            acqLitLiActionsSelector.attr('value', '_');
        });

    acqLitCreatePoSubmit.onClick = function() {
        acqLitPoCreateDialog.hide();
        self._createPO(acqLitPoCreateDialog.getValues());
    }

    acqLitSavePlButton.onClick = function() {
        acqLitSavePlDialog.hide();
        self._savePl(acqLitSavePlDialog.getValues());
    }

    acqLitCancelLiStateButton.onClick = function() {
        acqLitChangeLiStateDialog.hide();
    }
    acqLitSaveLiStateButton.onClick = function() {
        acqLitChangeLiStateDialog.hide();
        self._updateLiState(acqLitChangeLiStateDialog.getValues(), acqLitChangeLiStateDialog.attr('state'));
    }


    //dojo.byId('acq-lit-notes-new-button').onclick = function(){acqLitCreateLiNoteDialog.show();}

    dojo.byId('acq-lit-select-toggle').onclick = function(){self.toggleSelect()};
    dojo.byId('acq-lit-info-back-button').onclick = function(){self.show('list')};
    dojo.byId('acq-lit-copies-back-button').onclick = function(){self.show('list')};
    dojo.byId('acq-lit-notes-back-button').onclick = function(){self.show('list')};
    dojo.byId('acq-lit-real-copies-back-button').onclick = function(){self.show('list')};

    this.reset = function() {
        while(self.tbody.childNodes[0])
            self.tbody.removeChild(self.tbody.childNodes[0]);
        self.selectors = [];
        self.noteAcks = {};
    };
    
    this.setNext = function(handler) {
        var link = dojo.byId('acq-lit-next');
        if(handler) {
            dojo.style(link, 'visibility', 'visible');
            link.onclick = handler;
        } else {
            dojo.style(link, 'visibility', 'hidden');
        }
    };

    this.setPrev = function(handler) {
        var link = dojo.byId('acq-lit-prev');
        if(handler) {
            dojo.style(link, 'visibility', 'visible'); 
            link.onclick = handler; 
        } else {
            dojo.style(link, 'visibility', 'hidden');
        }
    };

    this.show = function(div) {
        openils.Util.hide('acq-lit-table-div');
        openils.Util.hide('acq-lit-info-div');
        openils.Util.hide('acq-lit-li-details');
        openils.Util.hide('acq-lit-notes-div');
        openils.Util.hide('acq-lit-real-copies-div');
        switch(div) {
            case 'list':
                openils.Util.show('acq-lit-table-div');
                break;
            case 'info':
                openils.Util.show('acq-lit-info-div');
                break;
            case 'copies':
                openils.Util.show('acq-lit-li-details');
                break;
            case 'real-copies':
                openils.Util.show('acq-lit-real-copies-div');
                break;
            case 'notes':
                openils.Util.show('acq-lit-notes-div');
                break;
            default:
                if(div) 
                    openils.Util.show(div);
        }
    }

    this.hide = function() {
        this.show(null);
    }

    this.toggleSelect = function() {
        if(self.toggleState) 
            dojo.forEach(self.selectors, function(i){i.checked = false});
        else 
            dojo.forEach(self.selectors, function(i){i.checked = true});
        self.toggleState = !self.toggleState;
    };


    /** @param all If true, assume all are selected */
    this.getSelected = function(all) {
        var selected = [];
        dojo.forEach(self.selectors, 
            function(i) { 
                if(i.checked || all)
                    selected.push(self.liCache[i.parentNode.parentNode.getAttribute('li')]);
            }
        );
        return selected;
    };

    this.setRowAttr = function(td, liWrapper, field, type) {
        var val = liWrapper.findAttr(field, type || 'lineitem_marc_attr_definition') || '';
        td.appendChild(document.createTextNode(val));
    };

    /**
     * Inserts a single lineitem into the growing table of lineitems
     * @param {Object} li The lineitem object to insert
     */
    this.addLineitem = function(li, skip_final_placement) {
        this.liCache[li.id()] = li;

        // sort the lineitem notes on edit_time
        if(!li.lineitem_notes()) li.lineitem_notes([]);

        var liWrapper = new openils.acq.Lineitem({lineitem:li});
        var row = self.rowTemplate.cloneNode(true);
        row.setAttribute('li', li.id());
        var tds = dojo.query('[attr]', row);
        dojo.forEach(tds, function(td) {self.setRowAttr(td, liWrapper, td.getAttribute('attr'), td.getAttribute('attr_type'));});
        dojo.query('[name=source_label]', row)[0].appendChild(document.createTextNode(li.source_label()));

        var isbn = liWrapper.findAttr('isbn', 'lineitem_marc_attr_definition');
        if(isbn) {
            // XXX media prefix for added content
            dojo.query('[name=jacket]', row)[0].setAttribute('src', '/opac/extras/ac/jacket/small/' + isbn);
        }

        dojo.query('[attr=title]', row)[0].onclick = function() {self.drawInfo(li.id())};
        dojo.query('[name=copieslink]', row)[0].onclick = function() {self.drawCopies(li.id())};
        dojo.query('[name=notes_count]', row)[0].innerHTML = li.lineitem_notes().length;
        dojo.query('[name=noteslink]', row)[0].onclick = function() {self.drawLiNotes(li)};

        // show which PO this lineitem is a member of
        if(li.purchase_order() && !this.isPO) {
            var po = 
                this.poCache[li.purchase_order()] =
                this.poCache[li.purchase_order()] ||
                fieldmapper.standardRequest(
                    ['open-ils.acq', 'open-ils.acq.purchase_order.retrieve'],
                    {params: [
                        this.authtoken, li.purchase_order(), {
                            "flesh_price_summary": true,
                            "flesh_lineitem_count": true
                        }
                    ]});
            if(po && !this.isMeta) {
                openils.Util.show(nodeByName('po', row), 'inline');
                var link = nodeByName('po_link', row);
                link.setAttribute('href', oilsBasePath + '/acq/po/view/' + li.purchase_order());
                link.innerHTML = 'PO: ' + po.name(); // TODO i18n
            }
        }

        // show which picklist this lineitem is a member of
        if(li.picklist() && (this.isPO || this.isMeta)) {
            var pl = 
                this.plCache[li.picklist()] = 
                this.plCache[li.picklist()] || 
                fieldmapper.standardRequest(
                    ['open-ils.acq', 'open-ils.acq.picklist.retrieve'],
                    {params: [this.authtoken, li.picklist()]});
            if(pl) {
                openils.Util.show(nodeByName('pl', row), 'inline');
                var link = nodeByName('pl_link', row);
                link.setAttribute('href', oilsBasePath + '/acq/picklist/view/' + li.picklist());
                link.innerHTML = 'PL: '+pl.name(); // TODO i18n
            }
        }

        var countNode = nodeByName('count', row);
        var count = li.item_count() || 0;
        if (typeof(this._copy_count_cb) == "function") {
            this._copy_count_cb(li.id(), count);
        }
        countNode.innerHTML = count;
        countNode.id = 'acq-lit-copy-count-label-' + li.id();

        // lineitem state
        nodeByName('li_state', row).innerHTML = li.state(); // TODO i18n state labels
        // lineitem price
        var priceInput = dojo.query('[name=price]', row)[0];
        var priceData = liWrapper.getPrice();
        priceInput.value = (priceData) ? priceData.price : '';
        priceInput.onchange = function() { self.updateLiPrice(priceInput, li) };

        // show either "mark received" or "unreceive" as appropriate
        this.updateLiReceivedness(li, row);

        if (!skip_final_placement) {
            self.tbody.appendChild(row);
            self.selectors.push(dojo.query('[name=selectbox]', row)[0]);
        } else {
            return row;
        }
    };

    this.updateLiReceivedness = function(li, row) {
        if (typeof(row) == "undefined")
            row = dojo.query('tr[li="' + li.id() + '"]', "acq-lit-tbody")[0];

        var recv_link = nodeByName("receive_link", row);
        var unrecv_link = nodeByName("unreceive_link", row);
        var real_copies_link = nodeByName("real_copies_link", row);

        /* handle row coloring for based on LI state */
        openils.Util.removeCSSClass(row, /^oils-acq-li-state-/);
        openils.Util.addCSSClass(row, "oils-acq-li-state-" + li.state());

        /* handle links that appear/disappear based on whether LI is received */
        if (this.isPO) {
            var self = this;
            switch(li.state()) {
                case "on-order":
                    openils.Util.hide(real_copies_link);
                    openils.Util.hide(unrecv_link);
                    openils.Util.show(recv_link, "inline");
                    recv_link.onclick = function() {
                        if (self.checkLiAlerts(li.id()))
                            self.issueReceive(li);
                    };
                    return;
                case "received":
                    openils.Util.hide(recv_link);
                    openils.Util.show(unrecv_link, "inline");
                    unrecv_link.onclick = function() {
                        if (confirm(localeStrings.UNRECEIVE_LI))
                            self.issueReceive(li, /* rollback */ true);
                    };
                    // TODO we should allow editing before receipt, in which case the
                    // test should be "if 1 or more real (acp) copies exist
                    openils.Util.show(real_copies_link);
                    real_copies_link.onclick = function() {
                        self.showRealCopies(li);
                    }
                    return;
            }
        }

        openils.Util.hide(recv_link);
        openils.Util.hide(unrecv_link);
        openils.Util.hide(real_copies_link);
    };


    this._setAlertStore = function() {
        acqLitNoteAlertSelector.store = new dojo.data.ItemFileReadStore(
            {
                "data": acqliat.toStoreData(
                    (new openils.PermaCrud()).search(
                        "acqliat", {"id": {"!=": null}}
                    )
                )
            }
        );
        acqLitNoteAlertSelector.setValue(); /* make the store "live" */
        acqLitNoteAlertSelector._store_ready = true;
    };

    /**
     * Draws and shows the lineitem notes pane
     */
    this.drawLiNotes = function(li) {
        var self = this;

        if (!acqLitNoteAlertSelector._store_ready) {
            this._setAlertStore();
        }

        li.lineitem_notes(
            li.lineitem_notes().sort(
                function(a, b) { 
                    if(a.edit_time() < b.edit_time()) return 1;
                    return -1;
                }
            )
        );

        while(this.liNotesTbody.childNodes[0])
            this.liNotesTbody.removeChild(this.liNotesTbody.childNodes[0]);
        this.show('notes');

        acqLitCreateLiNoteSubmit.onClick = function() {
            var value = acqLitCreateNoteText.attr('value');
            if(!value) return;
            var note = new fieldmapper.acqlin();
            note.isnew(true);
            note.value(value);
            note.lineitem(li.id());
            if (acqLitNoteAlertSelector.item)
                note.alert_text(Number(acqLitNoteAlertSelector.item.id));

            self.updateLiNotes(li, note);
        }

        dojo.byId('acq-lit-notes-save-button').onclick = function() {
            self.updateLiNotes(li);
        }

        dojo.forEach(li.lineitem_notes(), function(note) { self.addLiNote(li, note) });
    }

    /**
     * Draws a single lineitem note in the notes pane
     */
    this.addLiNote = function(li, note) {
        if(note.isdeleted()) return;
        var self = this;
        var row = self.liNotesRow.cloneNode(true);
        dojo.query('[name=value]', row)[0].innerHTML = note.value();

        dojo.query('[name=delete]', row)[0].onclick = function() {
            note.isdeleted(true);
            self.liNotesTbody.removeChild(row);
        };

        if(note.edit_time()) {
            dojo.query('[name=edit_time]', row)[0].innerHTML = 
                dojo.date.locale.format(
                    dojo.date.stamp.fromISOString(note.edit_time()), 
                    {formatLength:'short'});
        }

        self.liNotesTbody.appendChild(row);
    }

    /**
     * Updates any new/changed/deleted notes on the server
     */
    this.updateLiNotes = function(li, newNote) {

        var notes;
        if(newNote) {
            notes = [newNote];
        } else {
            notes = li.lineitem_notes().filter(
                function(note) {
                    if(note.ischanged() || note.isnew() || note.isdeleted())
                        return note;
                }
            );
        }

        if(notes.length == 0) return;
        progressDialog.show();

        fieldmapper.standardRequest(
            ['open-ils.acq', 'open-ils.acq.lineitem_note.cud.batch'],
            {   async : true,
                params : [this.authtoken, notes],
                onresponse : function(r) {
                    var resp = openils.Util.readResponse(r);

                    if(resp.complete) {

                        if(!newNote) {
                            // remove the old changed notes
                            var list = [];
                            dojo.forEach(li.lineitem_notes(), 
                                function(note) {
                                    if(!(note.ischanged() || note.isnew() || note.isdeleted()))
                                        list.push(note);
                                }
                            );
                            li.lineitem_notes(list);
                        }

                        progressDialog.hide();
                        self.drawLiNotes(li);
                        return;
                    }

                    progressDialog.update(resp);
                    var newnote = resp.note;

                    if(!newnote.isdeleted()) {
                        newnote.isnew(false);
                        newnote.ischanged(false);
                        li.lineitem_notes().push(newnote);
                    }
                },
            }
        );
    }

    this.updateLiPrice = function(input, li) {

        var price = input.value;
        var liWrapper = new openils.acq.Lineitem({lineitem:li});
        var oldPrice = liWrapper.getPrice() || null;

        if(oldPrice) oldPrice = oldPrice.price;
        if(price == oldPrice) return;

        fieldmapper.standardRequest(
            ['open-ils.acq', 'open-ils.acq.lineitem.price.set'],
            {   async : true,
                params : [this.authtoken, li.id(), price],
                oncomplete : function(r) {
                    openils.Util.readResponse(r);
                }
            }
        );
    }

    this.removeLineitem = function(liId) {
        this.tbody.removeChild(dojo.query('[li='+liId+']', this.tbody)[0]);
        delete this.liCache[liId];
        //selected.push(self.liCache[i.parentNode.parentNode.getAttribute('li')]);
    }

    this.drawInfo = function(liId) {
        this.show('info');
        openils.acq.Lineitem.fetchAttrDefs(
            function() { 
                self._fetchLineitem(liId, function(li){self._drawInfo(li);}); 
            } 
        );
    };

    this._fetchLineitem = function(liId, handler) {

        var li = this.liCache[liId];
        if(li && li.marc() && li.lineitem_details())
            return handler(li);
        
        fieldmapper.standardRequest(
            ['open-ils.acq', 'open-ils.acq.lineitem.retrieve'],
            {   async: true,

                params: [self.authtoken, liId, {
                    flesh_attrs: true,
                    flesh_li_details: true,
                    flesh_fund_debit: true }],

                oncomplete: function(r) {
                    var li = openils.Util.readResponse(r);
                    handler(li)
                }
            }
        );
    };

    this._drawInfo = function(li) {

        acqLitEditOrderMarc.onClick = function() { self.editOrderMarc(li); }

        if(li.eg_bib_id()) {
            openils.Util.hide('acq-lit-marc-order-record-label');
            openils.Util.hide(acqLitEditOrderMarc.domNode);
            openils.Util.show('acq-lit-marc-real-record-label');
        } else {
            openils.Util.show('acq-lit-marc-order-record-label');
            openils.Util.show(acqLitEditOrderMarc.domNode);
            openils.Util.hide('acq-lit-marc-real-record-label');
        }

        this.drawMarcHTML(li);
        this.infoTbody = dojo.byId('acq-lit-info-tbody');

        if(!this.infoRow)
            this.infoRow = this.infoTbody.removeChild(dojo.byId('acq-lit-info-row'));
        while(this.infoTbody.childNodes[0])
            this.infoTbody.removeChild(this.infoTbody.childNodes[0]);

        for(var i = 0; i < li.attributes().length; i++) {
            var attr = li.attributes()[i];
            var row = this.infoRow.cloneNode(true);

            var type = attr.attr_type().replace(/lineitem_(.*)_attr_definition/, '$1');
            var name = openils.acq.Lineitem.attrDefs[type].filter(
                function(a) {
                    return (a.code() == attr.attr_name());
                }
            ).pop().description();

            dojo.query('[name=label]', row)[0].appendChild(document.createTextNode(name));
            dojo.query('[name=value]', row)[0].appendChild(document.createTextNode(attr.attr_value()));
            this.infoTbody.appendChild(row);
        }

        if(li.eg_bib_id()) {
            openils.Util.show('acq-lit-info-cat-link');
            var link = dojo.byId('acq-lit-info-cat-link').getElementsByTagName('a')[0];

            if(openils.XUL.isXUL()) {

                var makeRecTab = function() {
				    xulG.new_tab(
                        XUL_OPAC_WRAPPER,
					    {tab_name: localeStrings.XUL_RECORD_DETAIL_PAGE, browser:false},
					    {
                            no_xulG : false, 
                            show_nav_buttons : true, 
                            show_print_button : true, 
                            opac_url : xulG.url_prefix(xulG.urls.opac_rdetail + '?r=' + li.eg_bib_id())
                        }
                    );
                }
                link.setAttribute('href', 'javascript:void(0);');
                link.onclick = makeRecTab;

            } else {
                var href = link.getAttribute('href');
                if(href.match(/=$/))
                    link.setAttribute('href',  href + li.eg_bib_id());
            }
        } else {
            openils.Util.hide('acq-lit-info-cat-link');
        }
    };

    this.drawMarcHTML = function(li) {
        var params = [null, true, li.marc()];
        if(li.eg_bib_id()) 
            params = [li.eg_bib_id(), true];

        fieldmapper.standardRequest(
            ['open-ils.search', 'open-ils.search.biblio.record.html'],
            {   async: true,
                params: params,
                oncomplete: function(r) {
                    dojo.byId('acq-lit-marc-div').innerHTML = 
                        openils.Util.readResponse(r);
                }
            }
        );
    }

    this.drawCopies = function(liId) {
        this.show('copies');
        var self = this;
        this.copyCache = {};
        this.copyWidgetCache = {};
        this.oldCopyWidgetCache = {};
        this.dfaCache = {};
        this.dfeOffset = 0;

        acqLitSaveCopies.onClick = function() { self.saveCopyChanges(liId) };
        acqLitBatchUpdateCopies.onClick = function() { self.batchCopyUpdate() };
        acqLitCopyCountInput.attr('value', '0');

        while(this.copyTbody.childNodes[0])
            this.copyTbody.removeChild(this.copyTbody.childNodes[0]);

        this._drawBatchCopyWidgets();

        this._fetchDistribFormulas(
            function() {
                openils.acq.Lineitem.fetchAttrDefs(
                    function() { 
                        self._fetchLineitem(liId, function(li){self._drawCopies(li);}); 
                    } 
                );
            }
        );
    };

    /**
     * Insert a new row into the distribution formula selection form
     */
    this._addDistribFormulaRow = function() {
        var self = this;

        if (!self.distribForms) {
            // no formulas, hide the form
            openils.Util.hide('acq-lit-distrib-formula-tbody');
            return;
        }

        if(!this.distribFormulaTemplate) 
            this.distribFormulaTemplate = 
                dojo.byId('acq-lit-distrib-formula-tbody').removeChild(dojo.byId('acq-lit-distrib-form-row'));

        var row = this.distribFormulaTemplate.cloneNode(true);
        dojo.place(row, "acq-lit-distrib-formula-tbody", "only");

        this.dfSelector = new dijit.form.FilteringSelect(
            {"labelAttr": "dynLabel", "labelType": "html"},
            nodeByName("selector", row)
        );
        this._updateFormulaStore();
        this.dfSelector.fetchProperties =
            {"sort": [{"attribute": "use_count", "descending": true}]};

        var apply = new dijit.form.Button(
            {"label": localeStrings.APPLY},
            nodeByName('set_button', row)
        ); 

        var reset = new dijit.form.Button(
            {"label": localeStrings.RESET_FORMULAE, "disabled": true},
            nodeByName("reset_button", row)  
        );

        dojo.connect(apply, 'onClick', 
            function() {
                var form_id = self.dfSelector.attr("value");
                if(!form_id) return;
                self._applyDistribFormula(form_id);
                reset.attr("disabled", false);
            }
        );

        dojo.connect(reset, 'onClick', 
            function() {
                self.restoreCopyFieldsBeforeDF();
                self.dfaCache = {};
                self.dfeOffset = 0;
                self._updateFormulaStore();
                reset.attr("disabled", "true");
            }
        );

    };

    /**
     * Applies a distrib formula to the current set of copies
     */
    this._applyDistribFormula = function(formula) {
        if(!formula) return;

        formula = this.distribForms.filter(
            function(form) { return form.id() == formula; }
        )[0];

        var copyRows = dojo.query('tr', self.copyTbody);

        if (this.dfeOffset >= copyRows.length) {
            alert(localeStrings.OUT_OF_COPIES);
            return;
        }

        var entries_applied = 0;
        for(
            var rowIndex = this.dfeOffset;
            rowIndex < copyRows.length;
            rowIndex++
        ) {
            
            var row = copyRows[rowIndex];
            var copy_id = row.getAttribute('copy_id');
            var copyWidgets = this.copyWidgetCache[copy_id];
            var entryIndex = this.dfeOffset;
            var entry = null;

            // find the correct entry for the current row
            dojo.forEach(formula.entries(), 
                function(e) {
                    if(!entry) {
                        entryIndex += e.item_count();
                        if(entryIndex > rowIndex)
                            entry = e;
                    }
                }
            );

            if(entry) {
                
                //console.log("rowIndex = " + rowIndex + ", entry = " + entry.id() + ", entryIndex=" + 
                //  entryIndex + ", owning_lib = " + entry.owning_lib() + ", location = " + entry.location());
    
                entries_applied++;
                this.saveCopyFieldsBeforeDF(copy_id);
                this._copy_fields_for_acqdf.forEach(
                    function(field) {
                        if(entry[field]()) {
                            copyWidgets[field].attr('value', (entry[field]()));
                        }
                    }
                );
            }
        }

        if (entries_applied) {
            this.dfaCache[formula.id()] = ++(this.dfaCache[formula.id()]) || 1;
            this._updateFormulaStore();
            this.dfeOffset += entries_applied;
        };
    };

    /**
     * This function updates the DF store for the dropdown so that use_counts
     * can reflect DF applications from this session before they're saved
     * server-side.
     */
    this._updateFormulaStore = function() {
        this.dfSelector.store = new dojo.data.ItemFileReadStore(
            {
                "data": self._labelFormulasWithCounts(
                    acqdf.toStoreData(self.distribForms)
                )
            }
        );
    };

    this.saveCopyFieldsBeforeDF = function(copy_id) {
        var self = this;
        if (!this.oldCopyWidgetCache[copy_id]) {
            var copyWidgets = this.copyWidgetCache[copy_id];

            this.oldCopyWidgetCache[copy_id] = {};
            this._copy_fields_for_acqdf.forEach(
                function(f) {
                    self.oldCopyWidgetCache[copy_id][f] =
                        copyWidgets[f].attr("value");
                }
            );
        }
    };

    this.restoreCopyFieldsBeforeDF = function() {
        var self = this;
        for (var copy_id in this.oldCopyWidgetCache) {
            this._copy_fields_for_acqdf.forEach(
                function(f) {
                    self.copyWidgetCache[copy_id][f].attr(
                        "value", self.oldCopyWidgetCache[copy_id][f]
                    );
                }
            );
        }
    };

    this._labelFormulasWithCounts = function(store_data) {
        for (var key in store_data.items) {
            var obj = store_data.items[key];
            obj.use_count = Number(obj.use_count); /* needed for sorting */

            if (this.dfaCache[obj.id])
                obj.use_count = obj.use_count + Number(this.dfaCache[obj.id]);

            obj.dynLabel = "<span class='acq-lit-distrib-form-use-count'>[" +
                obj.use_count + "]</span>&nbsp; " + obj.name;
        }
        return store_data;
    };

    /**
     * This method formerly would not refetch the DF formulas if they'd been
     * loaded already, but now it always re-fetches, since use_count changes.
     */
    this._fetchDistribFormulas = function(onload) {
        fieldmapper.standardRequest(
            ["open-ils.acq",
                "open-ils.acq.distribution_formula.ranged.retrieve.atomic"],
            {
                "async": true,
                "params": [openils.User.authtoken],
                "oncomplete": function(r) {
                    self.distribForms = openils.Util.readResponse(r);
                    if(!self.distribForms || self.distribForms.length == 0) {
                        self.distribForms = [];
                    }
                    self._addDistribFormulaRow();
                    onload();
                }
            }
        );
    }

    this._drawBatchCopyWidgets = function() {
        var row = this.copyBatchRow;
        dojo.forEach(liDetailBatchFields, 
            function(field) {
                if(self.copyBatchRowDrawn) {
                    self.copyBatchWidgets[field].attr('value', null);
                } else {
                    var widget = new openils.widget.AutoFieldWidget({
                        fmField : field,
                        fmClass : 'acqlid',
                        parentNode : dojo.query('[name='+field+']', row)[0],
                        orgLimitPerms : ['CREATE_PICKLIST'],
                        dijitArgs : {required:false},
                        forceSync : true
                    });
                    widget.build(
                        function(w, ww) {
                            self.copyBatchWidgets[field] = w;
                        }
                    );
                }
            }
        );
        this.copyBatchRowDrawn = true;
    };

    this.batchCopyUpdate = function() {
        var self = this;
        for(var k in this.copyWidgetCache) {
            var cache = this.copyWidgetCache[k];
            dojo.forEach(liDetailBatchFields, function(f) {
                var newval = self.copyBatchWidgets[f].attr('value');
                if(newval) cache[f].attr('value', newval);
            });
        }
    };

    this._drawCopies = function(li) {
        var self = this;

        // this button sets the total number of copies for a given lineitem
        acqLitAddCopyCount.onClick = function() { 
            var count = acqLitCopyCountInput.attr('value');

            // add new rows
            while(self.copyCount() < count)
                self.addCopy(li); 
            
            // delete rows if necessary
            var diff = self.copyCount() - count;
            if(diff > 0) {
                var rows = dojo.query('tr', self.copyTbody).reverse().slice(0, diff);
                if(confirm(dojo.string.substitute(localeStrings.DELETE_LI_COPIES_CONFIRM, [diff]))) {
                    dojo.forEach(rows, function(row) {self.deleteCopy(row); });
                } else {
                    acqLitCopyCountInput.attr('value', self.copyCount()+'');
                }
            }
        }


        if(li.lineitem_details().length > 0) {
            dojo.forEach(li.lineitem_details(),
                function(copy) {
                    self.addCopy(li, copy);
                }
            );
        } else {
            self.addCopy(li);
        }
    };

    this.copyCount = function() {
        var count = 0;
        for(var id in this.copyCache) {
            if(!this.copyCache[id].isdeleted())
                count++;
        }
        return count;
    }

    this.virtCopyId = -1;
    this.addCopy = function(li, copy) {
        var row = this.copyRow.cloneNode(true);
        this.copyTbody.appendChild(row);
        var self = this;

        if(!copy) {
            copy = new fieldmapper.acqlid();
            copy.isnew(true);
            copy.id(this.virtCopyId--);
            copy.lineitem(li.id());
        }

        this.copyCache[copy.id()] = copy;
        row.setAttribute('copy_id', copy.id());
        self.copyWidgetCache[copy.id()] = {};

        acqLitCopyCountInput.attr('value', self.copyCount()+'');

        dojo.forEach(liDetailFields,
            function(field) {
                var widget = new openils.widget.AutoFieldWidget({
                    fmObject : copy,
                    fmField : field,
                    fmClass : 'acqlid',
                    parentNode : dojo.query('[name='+field+']', row)[0],
                    orgLimitPerms : ['CREATE_PICKLIST', 'CREATE_PURCHASE_ORDER'],
                    readOnly : Boolean(copy.eg_copy_id())
                });
                widget.build(
                    // make sure we capture the value from any async widgets
                    function(w, ww) { 
                        copy[field](ww.getFormattedValue()) 
                        self.copyWidgetCache[copy.id()][field] = w;
                    }
                );
                dojo.connect(widget.widget, 'onChange', 
                    function(val) { 
                        if(copy.isnew() || val != copy[field]()) {
                            // prevent setting ischanged() automatically on widget load for existing copies
                            copy[field](widget.getFormattedValue()) 
                            copy.ischanged(true);
                        }
                    }
                );
            }
        );

        this.updateLidReceivedness(copy, row);
    };

    this.updateLidReceivedness = function(copy, row) {
        if (typeof(row) == "undefined") {
            row = dojo.query(
                'tr[copy_id="' + copy.id() + '"]', this.copyTbody
            )[0];
        }

        var self = this;
        var recv_link = nodeByName("receive", row);
        var unrecv_link = nodeByName("unreceive", row);
        var del_link = nodeByName("delete", row);

        if (this.isPO) {
            openils.Util.hide(del_link.parentNode);

            /* Avoid showing (un)receive links for virtual copies */
            if (copy.id() > 0) {
                if(copy.recv_time()) {
                    openils.Util.hide(recv_link);
                    openils.Util.show(unrecv_link);
                    unrecv_link.onclick = function() {
                        if (confirm(localeStrings.UNRECEIVE_LID))
                            self.issueReceive(copy, /* rollback */ true);
                    };
                } else {
                    openils.Util.hide(unrecv_link);
                    openils.Util.show(recv_link);
                    recv_link.onclick = function() {
                        if (self.checkLiAlerts(copy.lineitem()))
                            self.issueReceive(copy);
                    };
                }
            } else {
                openils.Util.hide(unrecv_link);
                openils.Util.hide(recv_link);
            }
        } else {
            openils.Util.hide(unrecv_link);
            openils.Util.hide(recv_link);

            del_link.onclick = function() { self.deleteCopy(row) };
            openils.Util.show(del_link.parentNode);
        }
    }

    this._confirmAlert = function(li, lin) {
        return confirm(
            dojo.string.substitute(
                localeStrings.CONFIRM_LI_ALERT, [
                    (new openils.acq.Lineitem({"lineitem": li})).findAttr(
                        "title", "lineitem_marc_attr_definition"
                    ),
                    lin.alert_text().description(), lin.value()
                ]
            )
        );
    };

    this.checkLiAlerts = function(li_id) {
        var li = this.liCache[li_id];

        var alert_notes = li.lineitem_notes().filter(
            function(o) { return Boolean(o.alert_text()); }
        );

        /* this is _intentionally_ not done in a call to forEach() ... */
        for (var i = 0; i < alert_notes.length; i++) {
            if (this.noteAcks[alert_notes[i].id()])
                continue;
            else if (!this._confirmAlert(li, alert_notes[i]))
                return false;
            else
                this.noteAcks[alert_notes[i].id()] = true;
        }

        return true;
    };

    this.deleteCopy = function(row) {
        var copy = this.copyCache[row.getAttribute('copy_id')];
        copy.isdeleted(true);
        if(copy.isnew())
            delete this.copyCache[copy.id()];
        this.copyTbody.removeChild(row);
    }

    this._dfaCacheAsList = function() {
        var L = [];
        for (var key in this.dfaCache) {
            for (var i = 0; i < this.dfaCache[key]; i++)
                L.push(key);
        }
        return L;
    }

    this.saveCopyChanges = function(liId) {
        var self = this;
        var copies = [];


        var total = 0;
        for(var id in this.copyCache) {
            var c = this.copyCache[id];
            if(!c.isdeleted()) total++;
            if(c.isnew() || c.ischanged() || c.isdeleted()) {
                if(c.id() < 0) c.id(null);
                copies.push(c);
            }
        }

        if (typeof(this._copy_count_cb) == "function") {
            this._copy_count_cb(liId, total);
        }

        dojo.byId('acq-lit-copy-count-label-' + liId).innerHTML = total;


        if (copies.length > 0) {
            openils.Util.show("acq-lit-update-copies-progress");
            fieldmapper.standardRequest(
                ['open-ils.acq', 'open-ils.acq.lineitem_detail.cud.batch'],
                {   async: true,
                    params: [openils.User.authtoken, copies],
                    onresponse: function(r) {
                        var res = openils.Util.readResponse(r);
                        litUpdateCopiesProgress.update(res);
                    },
                    oncomplete: function() {
                        self.drawCopies(liId);
                        openils.Util.hide("acq-lit-update-copies-progress");
                    }
                }
            );
        }

        var dfa_list = this._dfaCacheAsList();
        if (dfa_list.length > 0) {
            fieldmapper.standardRequest(
                ["open-ils.acq",
                "open-ils.acq.distribution_formula.record_application"],
                {
                    "async": true,
                    "params": [openils.User.authtoken, dfa_list, liId],
                    "onresponse": function(r) {
                        var res = openils.Util.readResponse(r);
                        if (res && res.length < dfa_list.length)
                            alert(localeStrings.DFA_NOT_ALL);
                    }
                }
            );
            this.dfaCache = {};
        }
    }

    this.applySelectedLiAction = function(action) {
        var self = this;
        switch(action) {

            case 'delete_selected':
                this._deleteLiList(self.getSelected());
                break;

            case 'create_order':

                if(!this.createPoProviderSelector) {
                    var widget = new openils.widget.AutoFieldWidget({
                        fmField : 'provider',
                        fmClass : 'acqpo',
                        searchFilter: {"active": "t"},
                        parentNode : dojo.byId('acq-lit-po-provider'),
                    });
                    widget.build(
                        function(w) { self.createPoProviderSelector = w; }
                    );
                }

                if(!this.createPoAgencySelector) {
                    var widget = new openils.widget.AutoFieldWidget({
                        fmField : 'ordering_agency',
                        fmClass : 'acqpo',
                        parentNode : dojo.byId('acq-lit-po-agency'),
                        orgLimitPerms : ['CREATE_PURCHASE_ORDER'],
                    });
                    widget.build(
                        function(w) { self.createPoAgencySelector = w; }
                    );
                }

         
                acqLitPoCreateDialog.show();
                break;

            case 'save_picklist':
                this._loadPLSelect();
                acqLitSavePlDialog.show();
                break;

            case 'selector_ready':
            case 'order_ready':
                acqLitChangeLiStateDialog.attr('state', action.replace('_', '-'));
                acqLitChangeLiStateDialog.show();
                break;

            case 'print_po':
                this.printPO();
                break;

            case 'receive_po':
                this.receivePO();
                break;

            case 'rollback_receive_po':
                this.rollbackPoReceive();
                break;

            case 'create_assets':
                this.createAssets();
                break;

            case 'export_attr_list':
                this.chooseExportAttr();
                break;

            case 'add_brief_record':
                if(this.isPO)
                    location.href = oilsBasePath + '/acq/picklist/brief_record?po=' + this.isPO;
                else
                    location.href = oilsBasePath + '/acq/picklist/brief_record?pl=' + this.isPL;
        }
    }

    this.createAssets = function() {
        if(!this.isPO) return;
        if(!confirm(localeStrings.CREATE_PO_ASSETS_CONFIRM)) return;
        this.show('acq-lit-progress-numbers');
        var self = this;
        fieldmapper.standardRequest(
            ['open-ils.acq', 'open-ils.acq.purchase_order.assets.create'],
            {   async: true,
                params: [this.authtoken, this.isPO],
                onresponse: function(r) {
                    var resp = openils.Util.readResponse(r);
                    self._updateProgressNumbers(resp, true);
                }
            }
        );
    }

    this.chooseExportAttr = function() {
        if (!acqLitExportAttrSelector._li_setup) {
            var self = this;
            acqLitExportAttrSelector.store = new dojo.data.ItemFileReadStore(
                {
                    "data": acqliad.toStoreData(
                        (new openils.PermaCrud()).search(
                            "acqliad", {"code": li_exportable_attrs}
                        )
                    )
                }
            );
            acqLitExportAttrSelector.setValue();
            acqLitExportAttrButton.onClick = function(){self.exportAttrList();};
            acqLitExportAttrSelector._li_setup = true;
        }
        openils.Util.show("acq-lit-export-attr-holder", "inline");
    };

    this.exportAttrList = function() {
        var attr_def = acqLitExportAttrSelector.item;
        var li_list = this.getSelected();
        var value_list = li_list.map(
            function(li) {
                return (new openils.acq.Lineitem({"lineitem": li})).findAttr(
                    attr_def.code, "lineitem_marc_attr_definition"
                );
            }
        ).filter(function(attr) { return Boolean(attr); });

        if (value_list.length > 0) {
            if (value_list.length < li_list.length) {
                if (!confirm(
                    dojo.string.substitute(
                        localeStrings.EXPORT_SHORT_LIST, [attr_def.description]
                    )
                )) {
                    return;
                }
            }
            try {
                openils.XUL.contentToFileSaveDialog(
                    value_list.join("\n"),
                    localeStrings.EXPORT_SAVE_DIALOG_TITLE
                );
            } catch (E) {
                alert(E);
            }
        } else {
            alert(dojo.string.substitute(
                localeStrings.EXPORT_EMPTY_LIST, [attr_def.description]
            ));
        }

        openils.Util.hide("acq-lit-export-attr-holder");
    };

    this.printPO = function() {
        if(!this.isPO) return;
        progressDialog.show(true);
        fieldmapper.standardRequest(
            ['open-ils.acq', 'open-ils.acq.purchase_order.format'],
            {   async: true,
                params: [this.authtoken, this.isPO, 'html'],
                oncomplete: function(r) {
                    progressDialog.hide();
                    var evt = openils.Util.readResponse(r);
                    if(evt && evt.template_output()) {
                        win = window.open('','', 'resizable,width=800,height=600,scrollbars=1');
                        win.document.body.innerHTML = evt.template_output().data();
                    }
                }
            }
        );
    }


    this.receivePO = function() {
        if (!this.isPO) return;

        for (var id in this.liCache) {
            /* assumption: liCache reflects exactly the
             * set of LIs that belong to our PO */
            if (this.liCache[id].state() != "received" &&
                !this.checkLiAlerts(id)) return;
        }

        this.show('acq-lit-progress-numbers');
        var self = this;
        fieldmapper.standardRequest(
            ['open-ils.acq', 'open-ils.acq.purchase_order.receive'],
            {   async: true,
                params: [this.authtoken, this.isPO],
                onresponse : function(r) {
                    var resp = openils.Util.readResponse(r);
                    self._updateProgressNumbers(resp, true);
                },
            }
        );
    }

    this.issueReceive = function(obj, rollback) {
        /* (For now) there shall be no marking LI or LIDs (un)received
         * except from the actual "view PO" interface. */
        if (!this.isPO) return;

        var part =
            {"jub": "lineitem", "acqlid": "lineitem_detail"}[obj.classname];
        var method =
            "open-ils.acq." + part + ".receive" + (rollback ? ".rollback" : "");

        progressDialog.show(true);
        fieldmapper.standardRequest(
            ["open-ils.acq", method], {
                "async": true,
                "params": [this.authtoken, obj.id()],
                "onresponse": function(r) {
                    self.handleReceive(openils.Util.readResponse(r));
                },
                "oncomplete": function() { progressDialog.hide(); }
            }
        );
    };

    /**
     * Handles the responses from receive and rollback ML calls.
     */
    this.handleReceive = function(resp) {
        if (resp) {
            if (resp.li) {
                for (var li_id in resp.li) {
                    for (var key in resp.li[li_id])
                        self.liCache[li_id][key](resp.li[li_id][key]);
                    self.updateLiReceivedness(self.liCache[li_id]);
                }
            }
            if (resp.po) {
                if (typeof(self.poUpdateCallback) == "function")
                    self.poUpdateCallback(resp.po);
            }
            if (resp.lid) {
                for (var lid_id in resp.lid) {
                    for (var key in resp.lid[lid_id])
                        self.copyCache[lid_id][key](resp.lid[lid_id][key]);
                    self.updateLidReceivedness(self.copyCache[lid_id]);
                }
            }
        }
    };

    this.rollbackPoReceive = function() {
        if(!this.isPO) return;
        if(!confirm(localeStrings.ROLLBACK_PO_RECEIVE_CONFIRM)) return;
        this.show('acq-lit-progress-numbers');
        var self = this;
        fieldmapper.standardRequest(
            ['open-ils.acq', 'open-ils.acq.purchase_order.receive.rollback'],
            {   async: true,
                params: [this.authtoken, this.isPO],
                onresponse : function(r) {
                    var resp = openils.Util.readResponse(r);
                    self._updateProgressNumbers(resp, true);
                },
            }
        );
    }

    this._updateProgressNumbers = function(resp, reloadOnComplete) {
        if(!resp) return;
        dojo.byId('acq-pl-lit-li-processed').innerHTML = resp.li;
        dojo.byId('acq-pl-lit-lid-processed').innerHTML = resp.lid;
        dojo.byId('acq-pl-lit-debits-processed').innerHTML = resp.debits_accrued;
        dojo.byId('acq-pl-lit-bibs-processed').innerHTML = resp.bibs;
        dojo.byId('acq-pl-lit-indexed-processed').innerHTML = resp.indexed;
        dojo.byId('acq-pl-lit-copies-processed').innerHTML = resp.copies;
        if(resp.complete && reloadOnComplete) 
            location.href = location.href;
    }


    this._createPO = function(fields) {
        this.show('acq-lit-progress-numbers');
        var po = new fieldmapper.acqpo();
        po.provider(this.createPoProviderSelector.attr('value'));
        po.ordering_agency(this.createPoAgencySelector.attr('value'));

        var selected = this.getSelected( (fields.create_from == 'all') );
        if(selected.length == 0) return;

        var max = selected.length * 3;

        var self = this;
        fieldmapper.standardRequest(
            ['open-ils.acq', 'open-ils.acq.purchase_order.create'],
            {   async: true,
                params: [
                    openils.User.authtoken, 
                    po, 
                    {
                        lineitems : selected.map(function(li) { return li.id() }),
                        create_assets : fields.create_assets[0],
                    }
                ],

                onresponse : function(r) {
                    var resp = openils.Util.readResponse(r);
                    self._updateProgressNumbers(resp);
                    if(resp.complete) 
                        location.href = oilsBasePath + '/eg/acq/po/view/' + resp.purchase_order.id();
                }
            }
        );
    }

    this._deleteLiList = function(list, idx) {
        if(idx == null) idx = 0;
        if(idx >= list.length) return;
        var liId = list[idx].id();
        fieldmapper.standardRequest(
            ['open-ils.acq', 'open-ils.acq.lineitem.delete'],
            {   async: true,
                params: [openils.User.authtoken, liId],
                oncomplete: function(r) {
                    self.removeLineitem(liId);
                    self._deleteLiList(list, ++idx);
                }
            }
        );
    }

    this.editOrderMarc = function(li) {

        /*  To run in Firefox directly, must set signed.applets.codebase_principal_support
            to true in about:config */

        if(!openils.XUL.enableXPConnect()) return;

        if(openils.XUL.isXUL()) {
            win = window.open('/xul/' + openils.XUL.buildId() + '/server/cat/marcedit.xul');
        } else {
            win = window.open('/xul/server/cat/marcedit.xul'); 
        }
        var self = this;
        win.xulG = {
            record : {marc : li.marc()},
            save : {
                label: 'Save Record', // XXX I18N
                func: function(xmlString) {
                    li.marc(xmlString);
                    fieldmapper.standardRequest(
                        ['open-ils.acq', 'open-ils.acq.lineitem.update'],
                        {   async: true,
                            params: [openils.User.authtoken, li],
                            oncomplete: function(r) {
                                openils.Util.readResponse(r);
                                win.close();
                                self.drawInfo(li.id())
                            }
                        }
                    );
                },
            }
        };
    }

    this._savePl = function(values) {
        var self = this;
        var selected = this.getSelected( (values.which == 'all') );
        openils.Util.show('acq-lit-generic-progress');

        if(values.new_name) {
            openils.acq.Picklist.create(
                {name: values.new_name}, 
                function(id) {
                    self._updateLiList(id, selected, 0, 
                        function(){
                            location.href = oilsBasePath + '/eg/acq/picklist/view/' + id;
                        });
                }
            );
        } else if(values.existing_pl) {
            // update lineitems to use an existing picklist
            self._updateLiList(values.existing_pl, selected, 0, 
                function(){
                    location.href = oilsBasePath + '/eg/acq/picklist/view/' + values.existing_pl;
                });
        }
    }

    this._updateLiState = function(values, state) {
        var self = this;
        var selected = this.getSelected( (values.which == 'all') );
        if(!selected.length) return;
        dojo.forEach(selected, function(li) {li.state(state);});
        self._updateLiList(null, selected, 0, 
            // TODO consider inline updates for efficiency
            function() { location.href = location.href }
        );
    }

    this._updateLiList = function(pl, list, idx, oncomplete) {
        if(idx >= list.length) return oncomplete();
        var li = list[idx];
        if(pl != null) li.picklist(pl);
        litGenericProgress.update({maximum: list.length, progress: idx});
        new openils.acq.Lineitem({lineitem:li}).update(
            function(r) {
                self._updateLiList(pl, list, ++idx, oncomplete);
            }
        );
    }

    this._loadPLSelect = function() {
        if(this._plSelectLoaded) return;
        var plList = [];
        function handleResponse(r) {
            plList.push(r.recv().content());
        }
        var method = 'open-ils.acq.picklist.user.retrieve';
        fieldmapper.standardRequest(
            ['open-ils.acq', method],
            {   async: true,
                params: [this.authtoken],
                onresponse: handleResponse,
                oncomplete: function() {
                    self._plSelectLoaded = true;
                    acqLitAddExistingSelect.store = 
                        new dojo.data.ItemFileReadStore({data:acqpl.toStoreData(plList)});
                    acqLitAddExistingSelect.setValue();
                }
            }
        );
    }

    // grab the li-details for this lineitem, grab the linked copies and volumes, add them to the table
    this.showRealCopies = function(li) {
        while(this.realCopiesTbody.childNodes[0])
            this.realCopiesTbody.removeChild(this.realCopiesTbody.childNodes[0]);
        this.show('real-copies');

        var pcrud = new openils.PermaCrud({authtoken : this.authtoken});
        this.realCopyList = [];
        this.volCache = {};
        var tabIndex = 1000;
        var self = this;

        acqLitSaveRealCopies.onClick = function() {
            self.saveRealCopies();
        }

        this._fetchLineitem(li.id(), 
            function(fullLi) {
                li = self.liCache[li.id()] = fullLi;

                pcrud.search(
                    'acp', {
                        id : li.lineitem_details().map(
                            function(item) { return item.eg_copy_id() }
                        )
                    }, {
                        async : true,
                        streaming : true,
                        onresponse : function(r) {
                            var copy = openils.Util.readResponse(r);
                            var volId = copy.call_number();
                            var volume = self.volCache[volId];
                            if(!volume) {
                                volume = self.volCache[volId] = pcrud.retrieve('acn', volId);
                            }
                            self.addRealCopy(volume, copy, tabIndex++);
                        }
                    }
                );
            }
        );
    }

    this.addRealCopy = function(volume, copy, tabIndex) {
        var row = this.realCopiesRow.cloneNode(true);
        this.realCopyList.push(copy);

        var selectNode;
        dojo.forEach(
            ['owning_lib', 'location', 'circ_modifier', 'label', 'barcode'],

            function(field) {
                var isvol = (field == 'owning_lib' || field == 'label');
                var widget = new openils.widget.AutoFieldWidget({
                    fmField : field,
                    fmObject : isvol ? volume : copy,
                    parentNode : nodeByName(field, row),
                    readOnly : (field != 'barcode'),
                });

                var widgetDrawn = null;

                if(field == 'barcode') {

                    widgetDrawn = function(w, ww) {
                        var node = w.domNode;
                        node.setAttribute('tabindex', ''+tabIndex);

                        // on enter, select the next barcode input
                        dojo.connect(w, 'onKeyDown',
                            function(e) {
                                if(e.keyCode == dojo.keys.ENTER) {
                                    var ti = node.getAttribute('tabindex');
                                    var nextNode = dojo.query('[tabindex=' + String(Number(ti) + 1) + ']', self.realCopiesTbody)[0];
                                    if(nextNode) nextNode.select();
                                }
                            }
                        );

                        dojo.connect(w, 'onChange', 
                            function(val) { 
                                if(!val || val == copy.barcode()) return;
                                copy.ischanged(true);
                                copy.barcode(val);
                            }
                        );


                        if(self.realCopiesTbody.getElementsByTagName('TR').length == 0)
                            selectNode = node;
                    }
                }

                widget.build(widgetDrawn);
            }
        );

        this.realCopiesTbody.appendChild(row);
        if(selectNode) selectNode.select();
    };

    this.saveRealCopies = function() {
        var pcrud = new openils.PermaCrud({authtoken : this.authtoken});
        progressDialog.show(true);
        var list = this.realCopyList.filter(function(copy) { return copy.ischanged(); });
        pcrud.update(list, {oncomplete: function() { 
            progressDialog.hide();
            self.show('list');
        }});
    }
}
