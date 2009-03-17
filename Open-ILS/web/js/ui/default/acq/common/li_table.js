dojo.require('openils.User');
dojo.require('openils.Util');
dojo.require('openils.acq.Lineitem');

function AcqLiTable() {

    var self = this;
    this.liCache = {};
    this.toggleState = false;
    this.tbody = dojo.byId('acq-lit-tbody');
    this.selectors = [];
    this.rowTemplate = this.tbody.removeChild(dojo.byId('acq-lit-row'));
    this.authtoken = openils.User.authtoken;
    dojo.byId('acq-lit-select-toggle').onclick = function(){self.toggleSelect()};

    this.reset = function() {
        while(self.tbody.childNodes[0])
            self.tbody.removeChild(self.tbody.childNodes[0]);
        self.selectors = [];
    };

    this.showTable = function() {
        dojo.style(dojo.byId('acq-lit-table-div'), 'display', 'block');
        dojo.style(dojo.byId('acq-lit-info-div'), 'display', 'none');
    };

    this.hideTable = function() {
        dojo.style(dojo.byId('acq-lit-table-div'), 'display', 'none');
    };

    this.showInfo = function() {
        self.hideTable();
        dojo.style(dojo.byId('acq-lit-info-div'), 'display', 'block');
    };

    this.toggleSelect = function() {
        if(self.toggleState) 
            dojo.forEach(self.selectors, function(i){i.checked = false});
        else 
            dojo.forEach(self.selectors, function(i){i.checked = true});
        self.toggleState = !self.toggleState;
    };

    this.getSelected = function() {
        var selected = [];
        dojo.forEach(self.selectors, 
            function(i) { 
                if(!i.checked) return;
                selected.push(self.liCache[i.parentNode.parentNode.getAttribute('li')]);
            }
        );
        return selected;
    };

    this.setRowAttr = function(td, liWrapper, field) {
        var val = liWrapper.findAttr(field, 'lineitem_marc_attr_definition') || '';
        td.appendChild(document.createTextNode(val));
    };

    this.addLineitem = function(li) {
        this.liCache[li.id()] = li;
        var liWrapper = new openils.acq.Lineitem({lineitem:li});
        var row = self.rowTemplate.cloneNode(true);
        row.setAttribute('li', li.id());
        var tds = dojo.query('[attr]', row);
        dojo.forEach(tds, function(td) {self.setRowAttr(td, liWrapper, td.getAttribute('attr'));});
        dojo.query('[name=source_label]', row)[0].appendChild(document.createTextNode(li.source_label()));
        var isbn = liWrapper.findAttr('isbn', 'lineitem_marc_attr_definition');
        if(isbn) {
            // XXX media prefix for added content
            dojo.query('[name=jacket]', row)[0].setAttribute('src', '/opac/extras/ac/jacket/small/' + isbn);
        }
        dojo.query('[attr=title]', row)[0].onclick = function() {self.drawInfo(li.id())};
        self.tbody.appendChild(row);
        self.selectors.push(dojo.query('[name=selectbox]', row)[0]);
    };

    this.drawInfo = function(liId) {
        //if(!this.liAttrDefs)

        this.showInfo();
        fieldmapper.standardRequest(
            ['open-ils.acq', 'open-ils.acq.lineitem.retrieve'],
            {   async: true,

                params: [self.authtoken, liId, {
                    flesh_attrs: true,
                    flesh_li_details: true,
                    flesh_fund: true,
                    flesh_fund_debit: true }],

                oncomplete: function(r) {
                    var li = openils.Util.readResponse(r);
                    self._drawInfo(li);
                }
            }
        );
    };

    this._drawInfo = function(li) {
        this.drawMarcHTML(li);
        this.infoTbody = dojo.byId('acq-lit-info-tbody');
        if(!this.infoRow)
            this.infoRow = this.infoTbody.removeChild(dojo.byId('acq-lit-info-row'));
        for(var i = 0; i < li.attributes().length; i++) {
            var attr = li.attributes()[i];
            var row = this.infoRow.cloneNode(true);
            dojo.query('[name=label]', row)[0].appendChild(document.createTextNode(attr.attr_name()));
            dojo.query('[name=value]', row)[0].appendChild(document.createTextNode(attr.attr_value()));
            this.infoTbody.appendChild(row);
        }
    };

    this.drawMarcHTML = function(li) {
        fieldmapper.standardRequest(
            ['open-ils.search', 'open-ils.search.biblio.record.html'],
            {   async: true,
                params: [null, true, li.marc()],
                oncomplete: function(r) {
                    dojo.byId('acq-lit-marc-div').innerHTML = 
                        openils.Util.readResponse(r);
                }
            }
        );
    }
}



