if (!dojo._hasResource["openils.widget.XULTermLoader"]) {
    dojo._hasResource["openils.widget.XULTermLoader"] = true;

    dojo.provide("openils.widget.XULTermLoader");
    dojo.require("openils.XUL");
    dojo.requireLocalization("openils.widget", "XULTermLoader");

    dojo.declare(
        "openils.widget.XULTermLoader", [dijit.layout.ContentPane], {
            "constructor": function(args) {
                this.args = args;
                this.terms = [];
                this._ = openils.widget.XULTermLoader.localeStrings;

                /* XXX Totally arbitrary defaults. Keeping them low for now
                 * since all search terms have to be turned into a URL.
                 * There will need to be a better long term solution.
                 */
                if (!this.args.fileSizeLimit)
                    this.args.fileSizeLimit = 2048;
                if (!this.args.termLimit)
                    this.args.termLimit = 100;
            },
            "build": function(callback) {
                var self = this;

                this.domNode = dojo.create("span");
                this.labelNode = dojo.create(
                    "span", {
                        "innerHTML": this._.LABEL_TEXT,
                        "style": "padding-right: 8px;"
                    }, this.domNode, "last"
                );
                this.countNode = dojo.create(
                    "span", {"innerHTML": this.terms.length},
                    this.labelNode, "first"
                );
                if (window.parent.IEMBEDXUL) {
                    this.buttonNode = dojo.create(
                        "input", {
                            "type" : "file",
                            "innerHTML": this._.BUTTON_TEXT,
                            "onchange": function(evt) { self.loadTerms(evt); }
                        },
                        this.domNode, "last"
                    );
                } else {
                    this.buttonNode = dojo.create(
                        "button", {
                            "innerHTML": this._.BUTTON_TEXT,
                            "onclick": function() { self.loadTerms(); }
                        },
                        this.domNode, "last"
                    );
                }

                if (this.args.parentNode)
                    dojo.place(this.domNode, this.args.parentNode, "last");

                callback(this);
            },
            "updateCount": function() {
                var value = this.attr("value");
                if (dojo.isArray(value))
                    this.terms = this.attr("value");
                this.countNode.innerHTML = this.terms.length;
            },
            "focus": function() {
                this.buttonNode.focus();
            },
            "loadTerms": function(evt) {
                try {
                    if (this.terms.length >= this.args.termLimit) {
                        alert(this._.TERM_LIMIT);
                        return;
                    }
                    var data;
                    var self = this;

                    function updateTermList() {
                        if (data.length + self.terms.length >=
                            self.args.termLimit) {
                            alert(self._.TERM_LIMIT_SOME);
                            var can = self.args.termLimit - self.terms.length;
                            if (can > 0)
                                self.terms = self.terms.concat(data.slice(0, can));
                        } else {
                            self.terms = self.terms.concat(data);
                        }
                        self.attr("value", self.terms);
                        self.updateCount();
                    }

                    if (evt && window.IAMBROWSER) {
                        var reader = new FileReader();
                        reader.onloadend = function(evt) {
                            data = self[
                                self.parseCSV ? "parseAsCSV" : "parseUnimaginatively"
                            ](evt.target.result);
                            updateTermList();
                        };
                        reader.readAsText(evt.target.files[0]);
                    } else {
                        data = this[
                            this.parseCSV ? "parseAsCSV" : "parseUnimaginatively"
                        ](
                            openils.XUL.contentFromFileOpenDialog(
                                this._.CHOOSE_FILE, this.args.fileSizeLimit
                            )
                        );
                        updateTermList();
                    }

                } catch(E) {
                    alert(E);
                }
            },
            "parseAsCSV": function(data) {
                return this.parseUnimaginatively(data).
                    map(
                        function(o) {
                            return o.match(/^".+"$/) ? o.slice(1,-1) : o;
                        }
                    ).
                    filter(
                        function(o) { return Boolean(o.match(/^\d+$/)); }
                    );
            },
            "parseUnimaginatively": function(data) {
                if (!data) return [];
                else return data.split("\n").
                    filter(function(o) { return o.length > 0; }).
                    map(function(o) {return o.replace("\r","").split(",")[0];}).
                    filter(function(o) { return o.length > 0; });
            }
        }
    );

    openils.widget.XULTermLoader.localeStrings =
        dojo.i18n.getLocalization("openils.widget", "XULTermLoader");
}
