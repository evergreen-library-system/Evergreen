// define our classes
function Vendor(name) {
    this.name = name;
    this.ebooks = [];
}

function Ebook(vendor, id) {
    this.vendor = vendor;
    this.id = id; // external ID for this title
    this.rec_id;  // bre.id for this title's MARC record
    this.title;   // title of ebook
    this.author;  // author of ebook
    this.avail;   // availability info for this title
    this.holdings = {}; // holdings info
    this.conns = {}; // references to Dojo event connection for performing actions with this ebook

}

Ebook.prototype.getDetails = function(callback) {
    var ses = dojo.cookie(this.vendor);
    var ebook = this;
    new OpenSRF.ClientSession('open-ils.ebook_api').request({
        method: 'open-ils.ebook_api.title.details',
        params: [ ses, ebook.id ],
        async: true,
        oncomplete: function(r) {
            var resp = r.recv();
            if (resp) {
                console.log('title details response: ' + resp.content());
                ebook.title = resp.content().title;
                ebook.author = resp.content().author;
                return callback(ebook);
            }
        }
    }).send();
}

Ebook.prototype.getAvailability = function(callback) {
    var ses = dojo.cookie(this.vendor);
    new OpenSRF.ClientSession('open-ils.ebook_api').request({
        method: 'open-ils.ebook_api.title.availability',
        params: [ ses, this.id ],
        async: true,
        oncomplete: function(r) {
            var resp = r.recv();
            if (resp) {
                console.log('availability response: ' + resp.content());
                this.avail = resp.content();
                return callback(resp.content());
            }
        }
    }).send();
}

Ebook.prototype.getHoldings = function(callback) {
    var ses = dojo.cookie(this.vendor);
    new OpenSRF.ClientSession('open-ils.ebook_api').request({
        method: 'open-ils.ebook_api.title.holdings',
        params: [ ses, this.id ],
        async: true,
        oncomplete: function(r) {
            var resp = r.recv();
            if (resp) {
                console.log('holdings response: ' + resp.content());
                this.holdings = resp.content();
                return callback(resp.content());
            }
        }
    }).send();
}

Ebook.prototype.checkout = function(authtoken, patron_id, callback) {
    var ses = dojo.cookie(this.vendor);
    var ebook = this;
    new OpenSRF.ClientSession('open-ils.ebook_api').request({
        method: 'open-ils.ebook_api.checkout',
        params: [ authtoken, ses, ebook.id, patron_id ],
        async: true,
        oncomplete: function(r) {
            var resp = r.recv();
            if (resp) {
                console.log('checkout response: ' + resp.content());
                return callback(resp.content());
            }
        }
    }).send();
}

Ebook.prototype.placeHold = function(authtoken, patron_id, callback) {
    var ses = dojo.cookie(this.vendor);
    var ebook = this;
    new OpenSRF.ClientSession('open-ils.ebook_api').request({
        method: 'open-ils.ebook_api.place_hold',
        params: [ authtoken, ses, ebook.id, patron_id, patron_email ],
        async: true,
        oncomplete: function(r) {
            var resp = r.recv();
            if (resp) {
                console.log('place hold response: ' + resp.content());
                return callback(resp.content());
            }
        }
    }).send();
}

Ebook.prototype.cancelHold = function(authtoken, patron_id, callback) {
    var ses = dojo.cookie(this.vendor);
    var ebook = this;
    new OpenSRF.ClientSession('open-ils.ebook_api').request({
        method: 'open-ils.ebook_api.cancel_hold',
        params: [ authtoken, ses, ebook.id, patron_id ],
        async: true,
        oncomplete: function(r) {
            var resp = r.recv();
            if (resp) {
                console.log('cancel hold response: ' + resp.content());
                return callback(resp.content());
            }
        }
    }).send();
}

