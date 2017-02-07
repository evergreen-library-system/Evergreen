// define our classes
function Vendor(name) {
    this.name = name;
    this.ebooks = [];
}

function Ebook(vendor, id) {
    this.vendor = vendor;
    this.id = id; // external ID for this title
    this.rec_id;  // bre.id for this title's MARC record
    this.avail;   // availability info for this title
    this.holdings = {}; // holdings info
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

