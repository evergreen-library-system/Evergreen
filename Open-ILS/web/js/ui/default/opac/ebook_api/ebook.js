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
    var ses = this.ses || dojo.cookie(this.vendor);
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
                if (typeof resp.content().formats !== 'undefined')
                    ebook.formats = resp.content().formats;
                return callback(ebook);
            }
        }
    }).send();
}

Ebook.prototype.getAvailability = function(callback) {
    var ses = this.ses || dojo.cookie(this.vendor);
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
    var ses = this.ses || dojo.cookie(this.vendor);
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
    var ses = this.ses || dojo.cookie(this.vendor);
    var ebook = this;
    // get selected checkout format (optional, used by OverDrive)
    var checkout_format;
    var format_selector = dojo.byId('checkout-format');
    if (format_selector) {
        checkout_format = format_selector.value;
    }
    // perform checkout
    new OpenSRF.ClientSession('open-ils.ebook_api').request({
        method: 'open-ils.ebook_api.checkout',
        params: [ authtoken, ses, ebook.id, patron_id, checkout_format ],
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
    var ses = this.ses || dojo.cookie(this.vendor);
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
    var ses = this.ses || dojo.cookie(this.vendor);
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

Ebook.prototype.download = function() {
    var ses = this.ses || dojo.cookie(this.vendor);
    var ebook = this;
    var request_link;
    var format_selector = dojo.byId('download-format');
    if (!format_selector) {
        console.log('could not find a specified format for download');
        return;
    } else {
        request_link = format_selector.value;
    }
    // Request links include params like "errorpageurl={errorpageurl}"
    // for redirecting the user if there's an error doing the download, etc.
    // In these scenarios we always redirect the user to the current page.
    // TODO: Add params to the current-page URL so that, if redirected, we
    // can detect those params on page reload and show a useful message.
    request_link = request_link.replace('{errorpageurl}', window.location.href);
    request_link = request_link.replace('{odreadauthurl}', window.location.href);
    // Now we're ready to request our download link.
    new OpenSRF.ClientSession('open-ils.ebook_api').request({
        method: 'open-ils.ebook_api.title.get_download_link',
        params: [ authtoken, ses, request_link ],
        async: true,
        oncomplete: function(r) {
            var resp = r.recv();
            if (resp) {
                if (resp.content().error_msg) {
                    console.log('download link request failed: ' + resp.content().error_msg);
                } else if (resp.content().url) {
                    var url = resp.content().url;
                    console.log('download link received: ' + url);
                    window.location = url;
                } else {
                    console.log('unknown error requesting download link');
                }
            }
        }
    }).send();
}

