/* Some really basic utils copied mostly from old opac js:
 * opac_utils.js, utils.js, misc.js (kcls). */
function _stub() { alert("XXX disconnected"); } /* for in progress work */

function $(id) { return document.getElementById(id); }
function $n(root, nodeName, attr) {
    return findNodeByName(root, nodeName, attr);
}

function findNodeByName(root, nodeName, /* defaults to "name" */attr) {
    if (!root || !nodeName) return null;
    if (root.nodeType != 1) return null;
    if (!attr) attr = "name";
    if (root.getAttribute(attr) == nodeName || root[attr] == nodeName)
        return root;

    for (var i = 0; i != root.childNodes.length; i++) {
        var n = findNodeByName(root.childNodes[i], nodeName);
        if (n) return n;
    }

    return null;
}

function swapCSSClass(obj, old, newc) {
	removeCSSClass(obj, old);
	addCSSClass(obj, newc);
}

function addCSSClass(e,c) {
    /* XXX I've seen much simpler implementation of this idea that just
     * do a regexp replace on e.className.  Any reason why we're making
     * it so hard here? I could see the justification if there's a certain
     * browser that doesn't cooperate. */
	if(!e || !c) return;

	var css_class_string = e.className;
	var css_class_array;

	if(css_class_string)
		css_class_array = css_class_string.split(/\s+/);

	var string_ip = ""; /*strip out nulls*/
	for (var css_class in css_class_array) {
		if (css_class_array[css_class] == c) { return; }
		if(css_class_array[css_class] !=null)
			string_ip += css_class_array[css_class] + " ";
	}
	string_ip += c;
	e.className = string_ip;
}

function removeCSSClass(e, c) {
	if(!e || !c) return;

	var css_class_string = '';

	var css_class_array = e.className;
	if( css_class_array )
		css_class_array = css_class_array.split(/\s+/);

	var first = 1;
	for (var css_class in css_class_array) {
		if (css_class_array[css_class] != c) {
			if (first == 1) {
				css_class_string = css_class_array[css_class];
				first = 0;
			} else {
				css_class_string = css_class_string + ' ' +
					css_class_array[css_class];
			}
		}
	}
	e.className = css_class_string;
}

function hideMe(obj) { addCSSClass(obj, "hide_me"); }
function unHideMe(obj) { removeCSSClass(obj, "hide_me"); }

function swapTabs(el) {
    if (!el) return;

    var tabs = [];
    for (var i = 0; i < el.parentNode.childNodes.length; i++) {
        var node = el.parentNode.childNodes[i];
        if (node.nodeType == 1 && node.nodeName.toLowerCase() == "a")
            tabs.push(node);
    }

    for (var n = 0; n < tabs.length; n++) {
        var i = tabs[n];
        if (i == el) {
            unHideMe($(i.rel));
            i.style.background = "url('/opac/skin/kcls/graphics/" +
                i.id + "_on.gif') no-repeat bottom";
        } else {
            hideMe($(i.rel));
            i.style.background = "url('/opac/skin/kcls/graphics/" +
                i.id + "_off.gif') no-repeat bottom";
        }
    }
}


/* Returns the character code pressed that caused the event. */
function grabCharCode(evt) {
    // OLD CODE: evt = (evt) ? evt : ((window.event) ? event : null);
    evt = evt || window.event || event || null;
    if (evt) {
    // OLD CODE: return (evt.charCode ? evt.charCode : ((evt.which) ? evt.which : evt.keyCode));
        return evt.which || evt.charCode || evt.keyCode;
    } else {
        return -1;
    }
}

/* returns true if the user pressed enter */
function userPressedEnter(evt) {
    var code = grabCharCode(evt);
    return (code == 13 || code == 3);
}

function setEnterFunc(node, func) {
    if (!(node && func)) return;
    node.onkeydown = function(evt) {
        if (userPressedEnter(evt)) func();
    };
}

function advAddGblRow() {
    var tbody = $("adv_global_tbody");
    var newrow = $("adv_global_trow").cloneNode(true);
    tbody.insertBefore(newrow, $("adv_global_addrow"));
    var input = $n(newrow, "term");
    input.value = "";
    setEnterFunc(input, _stub); /* XXX TODO make a real form and get rid of this? */
    $n(newrow, 'type').focus();
}

var rdetailNewBookbag = _stub; /* XXX TODO reimplement without JS? */
var addMyList = _stub; /* XXX TODO we probably still need this one */
var listSaveAction = _stub; /* XXX TODO we probably still need this one */
var expandBoxes = _stub; /* XXX TODO possibly reimplement or replace */
var iForgotMyPassword = _stub; /* XXX TODO possibly reimplement or replace */
var switchSubPage = _stub;
var myOPACRenewSelected = _stub;
var myOPACCreateBookbag = _stub;
var myOPACSavePrefs = _stub;
var myOPACUpdatePhone = _stub;  /* XXX TODOD myOPACUpdate*() and the buttons where
                                   the handlers are used should probably go
                                   away completely */
var myOPACUpdateUsername = _stub;
var myOPACUpdatePassword = _stub;
var myOPACUpdateEmail = _stub;
var myOPACUpdateHomeOU = _stub;
var myopacDoHoldAction = _stub;
var myopacApplyThawDate = _stub;
var showCachedList = _stub;
var searchBarSubmit = _stub;
var sortHolds = _stub; /* XXX TODO There was a method for sorting loaded holds
                          in the DOM without reloading the page, but it was
                          reliant on fieldmapper and some stock dojo
                          libraries.  Could be reimplemented without deps
                          if deemed worthwhile. */
var showDetailedResults = _stub; /* XXX TODO for an old onchange handler that
                                toggled between simple and detailed results
                                in the rresults page.  */
var checkAll = _stub;
var sortChecked = _stub;
var sortCheckedHist = _stub;
var showPaymentForm = _stub;
var showFinesDiv = _stub;
var fadeOut = _stub;    /* XXX TODO what the heck? not seen anywhere */
