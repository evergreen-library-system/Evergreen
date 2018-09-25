dojo.require("dojo.string");
dojo.require("dijit.form.Button");

var list_renderer;

function n(name, ctx) { return dojo.query("[name='" + name + "']", ctx)[0]; }

function ListRenderer() {
    var self = this;

    this.render = function() {
        var rendered_something = false;

        for (var i = 0; i < this.streams.length; i++) {
            var stream = this.streams[i];

            if (!this.users_by_stream[stream.id()])
                continue; /* no users on this stream */

            var list = dojo.clone(this.list_template);
            n("title", list).innerHTML = this.mvr.title();
            n("issuance_label", list).innerHTML = this.issuance.label();
            n("distribution_holding_lib", list).innerHTML =
                stream.distribution().holding_lib().shortname();
            n("distribution_label", list).innerHTML =
                stream.distribution().label();
            if (stream.routing_label()) {
                n("stream_routing_label", list).innerHTML =
                    stream.routing_label();
                openils.Util.show(
                    n("stream_routing_label", list), "inline"
                );
            } else {
                n("stream_id", list).innerHTML = stream.id();
                openils.Util.show(n("stream_id_container", list), "inline");
            }

            this.render_users(stream, list);

            if (rendered_something) {
                dojo.create(
                    "hr",
                    {"style": "page-break-after: always"}, this.target, "last"
                );
            }

            dojo.place(list, this.target, "last");
            rendered_something = true;
        }

        return this; /* for chaining */
    };

    this._render_reader_addresses = function(reader, node) {
        var used_ids = {};
        ["mailing", "billing"].forEach(
            function(addr_type) {
                var addr = reader[addr_type + "_address"]();
                if (!addr || !addr.valid() || used_ids[addr.id()])
                    return;

                used_ids[addr.id()] = true;

                var prefix = addr_type + "_address_";
                var container = n(prefix + "container", node);
                if (container)
                    openils.Util.show(container);

                ["street1", "street2", "city", "county", "state",
                    "country", "post_code"].forEach(
                    function(f) {
                        var field = prefix + f;
                        var target = n(field, node);
                        if (target)
                            target.innerHTML = addr[f]();
                    }
                );
            }
        );
    };

    this.render_users = function(stream, list) {
        for (var i = 0; i < this.users_by_stream[stream.id()].length; i++) {
            var user = this.users_by_stream[stream.id()][i];
            var node = dojo.clone(this.user_template);

            if (user.reader()) {
                n("barcode", node).innerHTML = user.reader().card().barcode();
                n("name", node).innerHTML = dojo.string.substitute(
                    "${0}, ${1} ${2}", [
                        user.reader().family_name(),
                        user.reader().first_given_name(),
                        user.reader().second_given_name()
                    ].map(function(n) { return n || ""; })
                );
                n("ou", node).innerHTML = user.reader().home_ou().shortname();

                this._render_reader_addresses(user.reader(), node);

                openils.Util.show(n("reader_container", node), "inline");
            } else if (user.department()) {
                n("department", node).innerHTML = user.department();
                openils.Util.show(n("department_container", node), "inline");
            }

            if (user.note()) {
                n("note", node).innerHTML = user.note();
                openils.Util.show(n("note_container", node), "inline");
            }

            dojo.place(node, n("users", list), "last");
        }
    };

    this.print = function() {
        this.print_target.print();
    }

    this._sort_users = function() {
        this.users_by_stream = {};
        this.users.forEach(
            function(user) {
                var key = user.stream();
                if (!self.users_by_stream[key])
                    self.users_by_stream[key] = [];
                self.users_by_stream[key].push(user);
            }
        );
    };

    /* Unfortunately, when we print the main window with dijits
     * wrapping everything, the page-break-* CSS properties don't work
     * inside of there, so we need an iframe to print from.
     */
    this._prepare_iframe = function() {
        var iframe = dojo.create(
            "iframe", {
                "src": "", "width": "100%", "height": "500", "frameborder": 0
            }, "iframe_in_here", "only"
        );

        iframe.contentWindow.document.open();
        iframe.contentWindow.document.write(
            "<html><head><link rel='stylesheet' href='" +
            dojo.byId("serials_stylesheet_link").href +
            "' type='text/css' />" +
            "</style></head>\n<body></body></html>"
        );
        iframe.contentWindow.document.close();
        this.target = iframe.contentWindow.document.body;
        this.print_target = iframe.contentWindow;
    };

    this._init = function(data) {
        this.user_template = dojo.byId("user_template");
        this.user_template.removeAttribute("id");
        this.user_template.parentNode.removeChild(this.user_template);

        this.list_template = dojo.byId("list_template");
        this.list_template.removeAttribute("id");
        this.list_template.parentNode.removeChild(this.list_template);

        dojo.mixin(this, data);

        this._sort_users();
        this._prepare_iframe();
    }

    this._init.apply(this, arguments);
}

function page_init() {
    list_renderer = new ListRenderer(xulG.routing_list_data);
    list_renderer.render().print();
}

openils.Util.addOnLoad(
    function() {
        // assume we're NOT in the web staff client if we have xulG
        if (typeof xulG !== 'undefined') return page_init();
    }
);
