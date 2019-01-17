function toggleAccordion(elm, alternate_elm) {
    var truncatedSpan;
    var ellipse;
    
    if (!alternate_elm) {
        var children = getSiblings(elm);
        for (i = 0; i < children.length; i++) {
            if (children[i].className == "truncated") {
                truncatedSpan = children[i];
            } else if (children[i].className == "truncEllipse") {
                ellipse = children[i];
            }
        }
    } else {
        truncatedSpan = iterateChildren(alternate_elm, 'truncated');
        ellipse = iterateChildren(alternate_elm, 'truncEllipse');
    }

    if (truncatedSpan.style.display == "none") {
        truncatedSpan.style.display = "inline";
        elm.innerHTML = eg_opac_i18n.EG_READ_LESS;
        ellipse.style.display = "none";
    } else {
        truncatedSpan.style.display = "none";
        elm.innerHTML = eg_opac_i18n.EG_READ_MORE;
        ellipse.style.display = "inline";
    }
}

function getSiblings(elm) {
    return Array.prototype.filter.call(elm.parentNode.children, function (sibling) {
		return sibling !== elm;
	});
}

function iterateChildren(elm, classname) {
    var child_to_return;
    if (elm.className == classname) return elm;
    for (i = 0; i < elm.children.length; i++) {
        if (elm.children[i].className == classname) {
            return elm.children[i];
        } else {
            child_to_return = iterateChildren(elm.children[i], classname);
        }
    }
    if (child_to_return) return child_to_return;
}