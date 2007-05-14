function createComplexHTMLElement (e, attrs, objects, text) {
        var l = document.createElementNS('http://www.w3.org/1999/xhtml',e);

        if (attrs) {
                for (var i in attrs) l.setAttribute(i,attrs[i]);
        }

        if (objects) {
                for ( var i in objects ) l.appendChild( objects[i] );
        }

        if (text) {
                l.appendChild( document.createTextNode(text) )
        }

        return l;
}

function createComplexXULElement (e, attrs, objects) {
        var l = document.createElementNS('http://www.mozilla.org/keymaster/gatekeeper/there.is.only.xul',e);

        if (attrs) {
                for (var i in attrs) {
                        if (typeof attrs[i] == 'function') {
                                l.addEventListener( i, attrs[i], true );
                        } else {
                                l.setAttribute(i,attrs[i]);
                        }
                }
        }

        if (objects) {
                for ( var i in objects ) l.appendChild( objects[i] );
        }

        return l;
}

function createDescription (attrs) {
        return createComplexXULElement('description', attrs, Array.prototype.slice.apply(arguments, [1]) );
}

function createTooltip (attrs) {
        return createComplexXULElement('tooltip', attrs, Array.prototype.slice.apply(arguments, [1]) );
}

function createLabel (attrs) {
        return createComplexXULElement('label', attrs, Array.prototype.slice.apply(arguments, [1]) );
}

function createVbox (attrs) {
        return createComplexXULElement('vbox', attrs, Array.prototype.slice.apply(arguments, [1]) );
}

function createHbox (attrs) {
        return createComplexXULElement('hbox', attrs, Array.prototype.slice.apply(arguments, [1]) );
}

function createRow (attrs) {
        return createComplexXULElement('row', attrs, Array.prototype.slice.apply(arguments, [1]) );
}

function createTextbox (attrs) {
        return createComplexXULElement('textbox', attrs, Array.prototype.slice.apply(arguments, [1]) );
}

function createCheckbox (attrs) {
        return createComplexXULElement('checkbox', attrs, Array.prototype.slice.apply(arguments, [1]) );
}

function createTreeChildren (attrs) {
        return createComplexXULElement('treechildren', attrs, Array.prototype.slice.apply(arguments, [1]) );
}

function createTreeItem (attrs) {
        return createComplexXULElement('treeitem', attrs, Array.prototype.slice.apply(arguments, [1]) );
}

function createTreeRow (attrs) {
        return createComplexXULElement('treerow', attrs, Array.prototype.slice.apply(arguments, [1]) );
}

function createTreeCell (attrs) {
        return createComplexXULElement('treecell', attrs, Array.prototype.slice.apply(arguments, [1]) );
}

function createPopup (attrs) {
        return createComplexXULElement('popup', attrs, Array.prototype.slice.apply(arguments, [1]) );
}

function createMenuPopup (attrs) {
        return createComplexXULElement('menupopup', attrs, Array.prototype.slice.apply(arguments, [1]) );
}

function createMenu (attrs) {
        return createComplexXULElement('menu', attrs, Array.prototype.slice.apply(arguments, [1]) );
}

function createMenuItem (attrs) {
        return createComplexXULElement('menuitem', attrs, Array.prototype.slice.apply(arguments, [1]) );
}

function createMenuSeparator (attrs) {
        return createComplexXULElement('menuseparator', attrs, Array.prototype.slice.apply(arguments, [1]) );
}


