function LiTablePager() {
    var self = this;

    this.init = function(fetcher, liTable, offset, limit) {
        this.fetcher = fetcher;
        this.liTable = liTable;
        this.limit = limit || 10;
        this.offset = offset || 0;

        dojo.byId("acq-litpager-controls-prev").onclick =
            function() { self.go(-1); }
        dojo.byId("acq-litpager-controls-next").onclick =
            function() { self.go(1); }
    };

    this.go = function(n /* generally (-1, 0, 1) */) {
        if (n) this.offset += n * this.limit;

        this.enableControls(false);

        [this.batch, this.total] = this.fetcher(this.offset, this.limit);

        if (this.batch.length) {
            this.liTable.reset(/* keep_selectors */ true);
            this.liTable.show("list");
            this.batch.forEach(function(li) { self.liTable.addLineitem(li); });
        }

        this.relabelControls();
        this.enableControls(true);
    };

    this.enableControls = function(yes) {
        dojo.byId("acq-litpager-controls-prev").disabled =
            (!yes) || this.offset < 1;
        dojo.byId("acq-litpager-controls-next").disabled =
            (!yes) || (
                (typeof(this.total) != "undefined") &&
                    this.offset + this.limit >= this.total
            );
        dojo.attr("acq-litpager-controls", "disabled", String(!yes));
    }

    this.relabelControls = function() {
        if (typeof(this.total) != "undefined") {
            dojo.byId("acq-litpager-controls-total").innerHTML = this.total;
            openils.Util.show("acq-litpager-controls-total-holder", "inline");
        } else {
            openils.Util.hide("acq-litpager-controls-total-holder");
        }

        if (this.batch && this.batch.length) {
            dojo.byId("acq-litpager-controls-batch-start").innerHTML =
                this.offset + 1;
            dojo.byId("acq-litpager-controls-batch-end").innerHTML =
                this.offset + this.batch.length;
            openils.Util.show("acq-litpager-controls-batch-range", "inline");
        } else {
            openils.Util.hide("acq-litpager-controls-batch-range");
        }
    };

    this.init.apply(this, arguments);
}
