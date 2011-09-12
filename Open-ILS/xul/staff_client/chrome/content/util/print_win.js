// Print Window Functions
// Loaded when print.js creates a window for printing

var params = window.arguments[0];
window.go_print = window.arguments[1];
var do_print = true;

function print_init(type) {
    if (typeof print_custom == "function") {
        print_custom(type);
    } else {
        print_do_sums();
        print_check_alt();
        print_check_noprint();
    }
    if (do_print) {
        go_print(window);
    } else {
        window.close();
    }
}

/* Example "swap slip" code
 * Use example:
 * <div altgroup="print1" altid="main">
 * <span altcheck="print1">%some_replace%</span>
 * <!-- Other slip stuff -->
 * </div>
 * <div altgroup="print1" altid="alt1" style="display: none">
 * <!-- Alt slip stuff -->
 * </div>
 * <div altgroup="print1" altid="alt2" style="display: none">
 * <!-- Second alt slip stuff -->
 * </div>
 * <div style="display: none">
 * <span alt="print1" altshow="alt1">Code1</span>
 * <span alt="print1" altshow="alt2">Code2</span>
 * </div>
 */
function print_check_alt() {
    var spans = document.getElementsByTagName('span');
    if(!spans) return;
    var groups_check = {};
    var foundgroups = false;
    for (var i = 0; i < spans.length; i++) {
        var group = spans[i].getAttribute('altcheck');
        if(group) {
            groups_check[group] = spans[i].textContent;
            foundgroups = true;
        }
    }
    if(!foundgroups) return;
    foundgroups = false;
    var groups_show = {};
    for (var i = 0; i < spans.length; i++) {
        var group = spans[i].getAttribute('alt');
        if(group && groups_check[group] && spans[i].textContent == groups_check[group]) {
            groups_show[group] = spans[i].getAttribute('altshow');
            foundgroups = true;
        }
    }
    if(!foundgroups) return;
    for (var i = 0; i < spans.length; i++) {
        var group = spans[i].getAttribute('altgroup');
        if(group && groups_check[group]) {
            spans[i].style.display = (groups_show[group] == spans[i].getAttribute('altid') ? '' : 'none');
        }
    }
    var divs = document.getElementsByTagName('div');
    if (!divs) return;
    for (var i = 0; i < divs.length; i++) {
        var group = divs[i].getAttribute('altgroup');
        if(group && groups_check[group]) {
            divs[i].style.display = (groups_show[group] == divs[i].getAttribute('altid') ? '' : 'none');
        }
    }
}

/* Example "don't print" code
 * Use example:
 * <!-- blah blah -->
 * <span noprintcheck="noprint1">%some_replace%</span>
 * <span noprintcheck="noprint2">%some_other_replace%</span>
 * <!-- blah blah -->
 * <div style="display: none">
 * <span noprint="noprint1">Code1</span>
 * <span noprint="noprint2">Code2</span>
 * </div>
 */
function print_check_noprint() {
    var spans = document.getElementsByTagName('span');
    if(!spans) return;
    var noprints = {};
    var foundnoprints = false;
    for (var i = 0; i < spans.length; i++) {
        var noprint = spans[i].getAttribute('noprintcheck');
        if(noprint) {
            noprints[noprint] = spans[i].textContent;
            foundnoprints = true;
        }
    }
    if(!foundnoprints) return;
    for (var i = 0; i < spans.length; i++) {
        var noprint = spans[i].getAttribute('noprint');
        if(noprint) {
            if(noprints[noprint] == spans[i].textContent) {
                do_print = false;
            }
        }
    }
}

/* Example "sum up" code
 * Use example:
 * <!-- blah blah -->
 * <!-- Probably as line_item entries: -->
 * <span sum="sum1">$5.00</span>
 * <span sum="sum1">$15.00</span>
 * <span sum="sum1">$25.00</span>
 * <!-- blah blah -->
 * $<span sumout="sum1" fixed="2"></span>
 */
function print_do_sums() {
    var spans = document.getElementsByTagName('span');
    if(!spans) return;
    var sums = {};
    var foundsums = false;
    for (var i = 0; i < spans.length; i++) {
        var sumset = spans[i].getAttribute("sum");
        if(sumset) {
            if(typeof sums[sumset] == 'undefined') {
                sums[sumset] = 0.0;
                foundsums = true;
            }
            var newVal = spans[i].textContent;
            // strip off a single non-digit character
            // Don't want to assume dollar sign
            // But don't strip a -
            newVal = newVal.replace(/^[^-0-9]/,'');
            newVal = parseFloat(newVal);
            if(!isNaN(newVal)) {
                sums[sumset] += newVal;
            }
        }
    }
    if(!foundsums) return;
    for (var i = 0; i < spans.length; i++) {
        var sumset = spans[i].getAttribute("sumout");
        if(sumset) {
            if(typeof sums[sumset] == 'undefined') {
                sums[sumset] = 0;
            }
            var fixed = spans[i].getAttribute("fixed");
            if(fixed) {
                fixed = parseInt(fixed);
                if(isNaN(fixed)) {
                    fixed = 0;
                }
                spans[i].textContent=sums[sumset].toFixed(fixed);
            } else {
                spans[i].textContent = sums[sumset];
            }
        }
    }
}
