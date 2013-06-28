var dialog;

function Bucketz39Dialog() {

    /**
     * builds the  Z39 sources and Z39 search indexes grid
    */
    this._build_options_grid = function(list, key, id_attr, label_attr) {

        // determine the number of columns per row dynamically
        var grid = dojo.byId(key).parentNode;
        var colcount = grid.getElementsByTagName('column').length;

        var row;
        dojo.forEach(list, function(obj, idx) {

            if (idx % colcount == 0) {
                row = dojo.create('row');
                dojo.byId(key).appendChild(row);
            }

            var attrs = {
                value : obj[id_attr](),
                label : obj[label_attr]()
            };
            attrs[key] = 1;

            row.appendChild(dojo.create('checkbox', attrs));
        });
    }

    /**
     * Fetches needed data
     */
    this.init = function() {
        var self = this;
        var pcrud = new OpenSRF.ClientSession('open-ils.pcrud');

        // vandelay queues
        pcrud.request({
            method : 'open-ils.pcrud.search.vbq.atomic',
            params : [
                this.authtoken, 
                {owner : this.user_id, queue_type : 'bib'}, 
                {order_by : {vbq : 'name'}}
            ],
            oncomplete : function(r) {
                if (resp = r.recv()) {
                    var qlist = resp.content();
                    dojo.forEach(qlist, function(q) {
                        var attrs = {label : q.name()};
                        var item = dojo.create('menuitem', attrs);
                        dojo.byId('queue_selector').appendChild(item);
                    });
                }
            }
        }).send();

        // z39 index field maps
        pcrud.request({
            method : 'open-ils.pcrud.search.czifm.atomic',
            params : [
                this.authtoken, 
                {id : {'!=' : null}}, 
                {order_by : {czifm : 'label'}}
            ],
            oncomplete : function(r) {
                self._build_options_grid(
                    r.recv().content(), 
                    'index_selector', 'id', 'label');
            }
        }).send();

        // z39 sources
        pcrud.request({
            method : 'open-ils.pcrud.search.czs.atomic',
            params : [
                this.authtoken, 
                {name : {'!=' : null}},
                {order_by : {czs : 'name'}}
            ],
            oncomplete : function(r) {
                self._build_options_grid(
                    r.recv().content(), 
                    'source_selector', 'name', 'label');
            }
        }).send();

        pcrud.request({
            method : 'open-ils.pcrud.search.vms.atomic',
            params : [this.authtoken, {
                owner : this._ws_ancestors(),
                mtype : 'biblio'
            }],
            oncomplete : function(r) {
                var sets = r.recv().content();
                dojo.forEach(sets, function(set) {
                    var attrs = {label : set.name(), value : set.id() };
                    var item = dojo.create('menuitem', attrs);
                    dojo.byId('match_set_selector').appendChild(item);
                });
            }
        }).send();

    }

    /* my workstation org unit plus ancestors as a flat list */
    this._ws_ancestors = function() {
        JSAN.use('OpenILS.data');
        var data = new OpenILS.data(); 
        data.stash_retrieve();
        var org = data.hash.aou[ this.ws_ou ]
        var org_list = [];

        while (org) {
            org_list.push(org.id());
            org = data.hash.aou[org.parent_ou()];
        }
        return org_list;
    }

    /**
     * extracts params from UI form elements
     */
    this._collect_params = function() {

        // request params
        var params = [this.authtoken, this.bucket_id];

        // Z39 sources
        params.push(dojo.query('[source_selector]').filter(
            function(cbox) { return cbox.checked }).map(
                function(cbox) { return cbox.getAttribute('value') }));

        // indexes
        params.push(dojo.query('[index_selector]').filter(
            function(cbox) { return cbox.checked }).map(
                function(cbox) { return cbox.getAttribute('value') }));

        params.push({
            // queue name (editable menulist)
            queue_name : dojo.byId('queue_selector').parentNode.value,
            // match set ID
            match_set : dojo.byId('match_set_selector').parentNode.value
        });

        return params;
    }

    this.submit = function() {
        var self = this;
        
        // progress labels
        this.search_bib_count = dojo.byId('search-bib-count');
        this.search_queue_count = dojo.byId('search-queue-count');
        this.search_progress = dojo.byId('search-progress');

        // hide submit row
        dojo.addClass(dojo.byId('search-submit-row'), 'hideme');

        // show progress rows
        dojo.forEach(
            dojo.query('.search_result_row'),
            function(row) { dojo.removeClass(row, 'hideme') }
        );

        var params = this._collect_params();
        dump('Submitting z39 search with: ' + js2JSON(params) + '\n');

        var ses = new OpenSRF.ClientSession('open-ils.search');
        ses.request({
            method : 'open-ils.search.z3950.bucket_search_queue',
            params : params,
            onresponse : function(r) {
                var resp = r.recv();
                if (!resp) return;
                var stat = resp.content();

                dojo.attr(self.search_bib_count, 'value', ''+stat.bre_count);
                dojo.attr(self.search_queue_count, 'value', ''+stat.queue_count);

                var scount = Number(stat.search_count);
                if (scount) {
                    dojo.attr(self.search_progress, 'value', ''+Math.floor(
                        (Number(stat.search_complete) / scount) * 100
                    ));
                }

                // queue object is returned in the final response
                self.queue = stat.queue;
            },
            oncomplete : function() {
                dojo.removeClass(dojo.byId('final-actions-row'), 'hideme');
            }
        }).send();
    }

    // Open a new XUL tab focused on the Vandelay queue containing the results.
    this.open_queue = function() {
        /*
        labelKey = labelKey || 'menu.cmd_open_conify.tab';
        var label = offlineStrings.getString(labelKey);
        */
        var label = 'MARC Import/Export'; // TODO
       
        // URL
        /*
        var url_prefix = this.xulG.url_prefix || window.url_prefix;
        */
        var urls = this.xulG.urls || window.urls;
        var loc = urls.XUL_BROWSER + '?url=' + 
            window.encodeURIComponent(
                this.xulG.url_prefix('EG_WEB_BASE/') +
                'vandelay/vandelay?qtype=bib&qid=' + this.queue.id()
            );
        
        var content_params = {
            'no_xulG': false,
            'show_print_button': true,
            'show_nav_buttons': true 
        };  
       
        this.xulG.new_tab(loc, {tab_name: label}, content_params);
        window.close();
    }
}

function my_init() {
    dialog = new Bucketz39Dialog();
    dialog.user_id   = window.arguments[0];
    dialog.authtoken = window.arguments[1];
    dialog.ws_ou     = window.arguments[2];
    dialog.bucket_id = window.arguments[3];
    dialog.xulG      = window.arguments[4];
    dialog.init();
}
