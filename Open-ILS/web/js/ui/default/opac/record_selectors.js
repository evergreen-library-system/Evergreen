;(function () {

    var rec_selector_block = document.getElementById("record_selector_block");
    var rec_selectors = document.getElementsByClassName("result_record_selector");
    var mylist_action_links = document.getElementsByClassName("mylist_action");
    var record_basket_count_el = document.getElementById('record_basket_count');
    var selected_records_count_el = document.getElementById('selected_records_count');
    var select_all_records_el = document.getElementById('select_all_records');
    var clear_basket_el = document.getElementById('clear_basket');
    var select_action_el = document.getElementById('select_basket_action');
    var do_basket_action_el = document.getElementById('do_basket_action');
    var mylist = [];

    function initialize() {
        var req = new window.XMLHttpRequest();
        req.open('GET', '/eg/opac/api/mylist/retrieve');
        if (('responseType' in req) && (req.responseType = 'json')) {
            req.onload = function (evt) {
                var result = req.response;
                handleUpdate(result);
                syncPageState();
            }
        } else {
            // IE 10/11
            req.onload = function (evt) {
                var result = JSON.parse(req.responseText);
                handleUpdate(result);
                syncPageState();
            }
        }
        req.send();
    }
    initialize();

    function syncPageState() {
        var all_checked = true;
        var legacy_adjusted = false;
        [].forEach.call(rec_selectors, function(el) {
            el.checked = mylist.includes(parseInt(el.value));
            if (el.checked) {
                adjustLegacyControlsVis('checked', el.value);
            } else {
                all_checked = false;
                adjustLegacyControlsVis('unchecked', el.value);
            }
            toggleRowHighlighting(el);
            legacy_adjusted = true;
        });
        if (!legacy_adjusted) {
            [].forEach.call(mylist_action_links, function(el) {
                if ('dataset' in el) {
                    if (el.dataset.action == 'delete') return;
                    // only need to do this once
                    var op = mylist.includes(parseInt(el.dataset.recid)) ? 'checked' : 'unchecked';
                    adjustLegacyControlsVis(op, el.dataset.recid);
                }
            });
        }
        if (select_all_records_el && rec_selectors.length) {
            select_all_records_el.checked = all_checked;
        }
        checkMaxCartSize();
    }

    function handleUpdate(result) {
        if (result) {
            mylist = result.mylist;
            if (selected_records_count_el) {
                selected_records_count_el.innerHTML = mylist.length;
            }
            if (clear_basket_el) {
                if (mylist.length > 0) {
                    clear_basket_el.classList.remove('hidden');
                } else {
                    clear_basket_el.classList.add('hidden');
                }
            }
            if (select_action_el) {
                if (mylist.length > 0) {
                    select_action_el.removeAttribute('disabled');
                } else {
                    select_action_el.setAttribute('disabled', 'disabled');
                }
            }
            if (do_basket_action_el) {
                if (mylist.length > 0) {
                    do_basket_action_el.removeAttribute('disabled');
                } else {
                    do_basket_action_el.setAttribute('disabled', 'disabled');
                }
            }
            if (record_basket_count_el) {
                record_basket_count_el.innerHTML = mylist.length;
            }
            checkMaxCartSize();
        }
    }

    function mungeList(op, rec, resync) {
        console.debug('calling mungeList to ' + op + ' record ' + rec);
        var req = new window.XMLHttpRequest();
        if (Array.isArray(rec)) {
            var qrec = rec.map(function(rec) {
                         return 'record=' + encodeURIComponent(rec);
                       }).join('&');
        } else {
            var qrec = 'record=' + encodeURIComponent(rec);
        }
        req.open('GET', '/eg/opac/api/mylist/' + op + '?' + qrec);
        if (('responseType' in req) && (req.responseType = 'json')) {
            req.onload = function (evt) {
                var result = req.response;
                handleUpdate(result);
                if (resync) syncPageState();
            }
        } else {
            // IE 10/11
            req.onload = function (evt) {
                var result = JSON.parse(req.responseText);
                handleUpdate(result);
                if (resync) syncPageState();
            }
        }
        req.send();
    }

    function adjustLegacyControlsVis(op, rec) {
        if (op == 'add' || op == 'checked') {
            var t;
            if (t = document.getElementById('mylist_add_' + rec)) {
                t.classList.add('hidden');
                document.getElementById('mylist_delete_' + rec).focus();
            }
            if (t = document.getElementById('mylist_delete_' + rec)) {
                t.classList.remove('hidden');
                document.getElementById('mylist_add_' + rec).focus();
            }
        } else if (op == 'delete' || op == 'unchecked') {
            if (t = document.getElementById('mylist_add_' + rec)) t.classList.remove('hidden');
            if (t = document.getElementById('mylist_delete_' + rec)) t.classList.add('hidden');
        }

        if (mylist.length > 0) {
            document.getElementById('mybasket').classList.remove('hidden');
        } else {
            document.getElementById('mybasket').classList.add('hidden');
        }
    }

    function findAncestorWithClass(el, cls) {
        while ((el = el.parentElement) && !el.classList.contains(cls));
        return el;
    }
    function toggleRowHighlighting(el) {
        var row = findAncestorWithClass(el, "result_table_row");
        if (!row) return;
        if (el.checked) {
            row.classList.add('result_table_row_selected');
        } else {
            row.classList.remove('result_table_row_selected');
        }
    }

    function checkMaxCartSize() {
        if ((typeof max_cart_size === 'undefined') || !max_cart_size) return;
        var alertel = document.getElementById('hit_selected_record_limit');
        [].forEach.call(rec_selectors, function(el) {
            if (!el.checked) el.disabled = (mylist.length >= max_cart_size);
        });
        [].forEach.call(mylist_action_links, function(el) {
            if ('dataset' in el && el.dataset.action == 'add') {
                if (mylist.length >= max_cart_size) {
                    // hide the add link
                    el.classList.add('hidden');
                } else {
                    // show the add link unless the record is
                    // already in the cart
                    if (!mylist.includes(parseInt(el.dataset.recid))) el.classList.remove('hidden');
                }
            }
        });
        if (mylist.length >= max_cart_size) {
            if (alertel) alertel.classList.remove('hidden');
            if (select_all_records_el && !select_all_records_el.checked) {
                select_all_records_el.disabled = true;
            }
        } else {
            if (alertel) alertel.classList.add('hidden');
            if (select_all_records_el) select_all_records_el.disabled = false;
        }
    }

    var all_checked = true;
    [].forEach.call(rec_selectors, function(el) {
        el.addEventListener("click", function() {
            if (this.checked) {
                mungeList('add', this.value);
                adjustLegacyControlsVis('add', this.value);
            } else {
                mungeList('delete', this.value);
                adjustLegacyControlsVis('delete', this.value);
            }
            toggleRowHighlighting(el);
        }, false);
        el.classList.remove("hidden");
        if (!el.checked) all_checked = false;
    });
    if (select_all_records_el && rec_selectors.length) {
        select_all_records_el.checked = all_checked;
    }
    if (rec_selector_block) rec_selector_block.classList.remove("hidden");

    function deselectSelectedOnPage() {
        var to_del = [];
        [].forEach.call(rec_selectors, function(el) {
            if (el.checked) {
                el.checked = false;
                adjustLegacyControlsVis('delete', el.value);
                toggleRowHighlighting(el);
                to_del.push(el.value);
            }
        });
        if (to_del.length > 0) {
            mungeList('delete', to_del);
        }
    }

    if (select_all_records_el) {
        select_all_records_el.addEventListener('click', function() {
            if (this.checked) {
                // adding
                var to_add = [];
                [].forEach.call(rec_selectors, function(el) {
                    if (!el.checked) {
                        el.checked = true;
                        adjustLegacyControlsVis('add', el.value);
                        toggleRowHighlighting(el);
                        to_add.push(el.value);
                    }
                });
                if (to_add.length > 0) {
                    mungeList('add', to_add);
                }
            } else {
                // deleting
                deselectSelectedOnPage();
            }
        });
    }

    function clearCart() {
        var req = new window.XMLHttpRequest();
        req.open('GET', '/eg/opac/api/mylist/clear');
        if (('responseType' in req) && (req.responseType = 'json')) {
            req.onload = function (evt) {
                var result = req.response;
                handleUpdate(result);
                syncPageState();
            }
        } else {
            // IE 10/11
            req.onload = function (evt) {
                var result = JSON.parse(req.responseText);
                handleUpdate(result);
                syncPageState();
            }
        }
        req.send();
    }

    if (clear_basket_el) {
        clear_basket_el.addEventListener('click', function() {
            if (confirm(window.egStrings['CONFIRM_BASKET_EMPTY'])) {
                clearCart();
            }
        });
    }

    [].forEach.call(mylist_action_links, function(el) {
        el.addEventListener("click", function(evt) {
            var recid;
            var action;
            if ('dataset' in el) {
                recid = el.dataset.recid;
                action = el.dataset.action;
                mungeList(action, recid, true);
                evt.preventDefault();
            }
        });
    });

    if (do_basket_action_el) {
        do_basket_action_el.addEventListener('click', function(evt) {
            if (select_action_el.options[select_action_el.selectedIndex].value) { 
                window.location.href = select_action_el.options[select_action_el.selectedIndex].value;
            }
            evt.preventDefault();
        });
    }

})();
