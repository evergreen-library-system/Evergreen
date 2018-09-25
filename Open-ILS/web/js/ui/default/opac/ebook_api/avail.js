dojo.addOnLoad(function() {

    // detect ebooks on current page for each vendor
    dojo.forEach(vendor_list, function(v) {
        var vendor = new Vendor(v);
        var ebook_nodes = dojo.query("." + v + "_avail");
        console.log('found ' + ebook_nodes.length + ' ebooks on this page');

        // we have ebooks for this vendor, so let's get availability info etc.
        if (ebook_nodes.length > 0) {
            checkSession(v, function(v,ses) {
                ebook_nodes.forEach(function(node) {
                    var ebook = new Ebook(v, node.getAttribute("id"));
                    ebook.rec_id = node.parentNode.getAttribute("id");
                    vendor.ebooks.push(ebook);

                    ebook.getHoldings( function(holdings) {
                        if (typeof holdings.available !== 'undefined') {
                            var avail = holdings.available;
                            if (avail == 1) {
                                node.innerHTML = 'This title is available online.';
                                dojo.removeClass(ebook.rec_id + '_ebook_checkout', "hidden");
                            } else if (avail == 0) {
                                node.innerHTML = 'This title is not currently available.';
                                dojo.removeClass(ebook.rec_id + '_ebook_place_hold', "hidden");
                            } else {
                                console.log(ebook.id + ' has bad availability: ' + avail);
                            }
                        } else {
                            if (holdings.formats.length > 0) {
                                var formats_ul = dojo.create("ul", null, ebook.rec_id + '_formats');
                                dojo.forEach(holdings.formats, function(f) {
                                    dojo.create("li", { innerHTML: f.name }, formats_ul);
                                });
                                var status_node = dojo.byId(ebook.rec_id + '_status');
                                var status_str = holdings.copies_available + ' of ' + holdings.copies_owned + ' available';
                                status_node.innerHTML = status_str;
                                dojo.removeClass(ebook.rec_id + '_ebook_holdings', "hidden");
                                if (holdings.copies_available > 0) {
                                    dojo.removeClass(ebook.rec_id + '_ebook_checkout', "hidden");
                                } else {
                                    dojo.removeClass(ebook.rec_id + '_ebook_place_hold', "hidden");
                                }
                            }
                        }
                        // unhide holdings/availability info now that it's populated
                        removeClass(node.parentNode, "hidden");
                    });
                });
            });
        }
    });

});
