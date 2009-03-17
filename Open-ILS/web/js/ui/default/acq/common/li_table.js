dojo.require('openils.acq.Lineitem');

function AcqLiTable() {

    var self = this;
    this.liCache = {};
    this.toggleState = false;
    this.tbody = dojo.byId('acq-lit-tbody');
    this.selectors = [];
    this.rowTemplate = this.tbody.removeChild(dojo.byId('acq-lit-row'));
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
        self.tbody.appendChild(row);
        self.selectors.push(dojo.query('[name=selectbox]', row)[0]);
    };
}



