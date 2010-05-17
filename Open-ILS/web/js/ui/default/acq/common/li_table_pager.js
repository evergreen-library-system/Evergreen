function LiTablePager() {
    var self = this;

    this.init = function(dataLoader, liTable, offset, limit) {
        this.dataLoader = dataLoader;
        this.liTable = liTable;
        this.displayLimit = limit || 15;
        this.displayOffset = offset || 0;

        dojo.byId("acq-litpager-controls-prev").onclick =
            function() { self.go(-1); }
        dojo.byId("acq-litpager-controls-next").onclick =
            function() { self.go(1); }
    };

    this.go = function(n /* generally (-1, 0, 1) */) {
        if (n) this.displayOffset += n * this.displayLimit;

        this.show();
        this.dataLoader(this); /* not a normal method, but a callback */
        this.enableControls(true);
        this.relabelControls();
    };

    this.show = function() {
        this.liTable.reset(/* keep_selectors */ true);
        this.liTable.show("list");
    };

    this.enableControls = function(yes) {
        dojo.byId("acq-litpager-controls-prev").disabled =
            (!yes) || this.displayOffset < 1;
        dojo.byId("acq-litpager-controls-next").disabled =
            (!yes) || (
                (typeof(this.total) != "undefined") &&
                    this.displayOffset + this.displayLimit >= this.total
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

        if (this.batch_length) {
            dojo.byId("acq-litpager-controls-batch-start").innerHTML =
                this.displayOffset + 1;
            dojo.byId("acq-litpager-controls-batch-end").innerHTML =
                this.displayOffset + this.batch_length;
            openils.Util.show("acq-litpager-controls-batch-range", "inline");
        } else {
            openils.Util.hide("acq-litpager-controls-batch-range");
        }
    };

    this.init.apply(this, arguments);
}
