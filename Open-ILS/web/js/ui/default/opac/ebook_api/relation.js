function Relation(vendor, patron_id) {
    this.vendor = vendor;
    this.patron_id = patron_id;
    this.checkouts = [];
    this.holds_pending = [];
    this.holds_ready = [];
}

Relation.prototype.getCheckouts = function(callback) {
    var ses = dojo.cookie(this.vendor);
    var rel = this;
    new OpenSRF.ClientSession('open-ils.ebook_api').request({
        method: 'open-ils.ebook_api.patron.get_checkouts',
        params: [ authtoken, ses, rel.patron_id ],
        async: false,
        oncomplete: function(r) {
            var resp = r.recv();
            if (resp) {
                console.log('retrieved checkouts for patron');
                rel.checkouts = [];
                dojo.forEach(resp.content(), function(checkout) {
                    checkout.vendor = rel.vendor;
                    rel.checkouts.push(checkout);
                });
                return callback(rel);
            }
        }
    }).send();
}

Relation.prototype.getHolds = function(callback) {
    var ses = dojo.cookie(this.vendor);
    var rel = this;
    new OpenSRF.ClientSession('open-ils.ebook_api').request({
        method: 'open-ils.ebook_api.patron.get_holds',
        params: [ authtoken, ses, rel.patron_id ],
        async: false,
        oncomplete: function(r) {
            var resp = r.recv();
            if (resp) {
                console.log('retrieved holds for patron');
                dojo.forEach(resp.content(), function(hold) {
                    hold.vendor = rel.vendor;
                    if (hold.is_ready === 1) {
                        rel.holds_ready.push(hold);
                    } else {
                        rel.holds_pending.push(hold);
                    }
                });
                return callback(rel);
            }
        }
    }).send();
}

Relation.prototype.getTransactions = function(callback) {
    var ses = dojo.cookie(this.vendor);
    var rel = this;
    new OpenSRF.ClientSession('open-ils.ebook_api').request({
        method: 'open-ils.ebook_api.patron.get_transactions',
        params: [ authtoken, ses, rel.patron_id ],
        async: false,
        oncomplete: function(r) {
            var resp = r.recv();
            if (resp) {
                console.log('retrieved holds for patron');
                var xacts = resp.content();
                dojo.forEach(xacts.checkouts, function(checkout) {
                    checkout.vendor = rel.vendor;
                    rel.checkouts.push(checkout);
                });
                dojo.forEach(xacts.holds, function(hold) {
                    hold.vendor = rel.vendor;
                    if (hold.is_ready === 1) {
                        rel.holds_ready.push(hold);
                    } else {
                        rel.holds_pending.push(hold);
                    }
                });
                return callback(rel);
            }
        }
    }).send();
}
