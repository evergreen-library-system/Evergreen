function $ () {
	var elements = new Array();

	for (var i = 0; i < arguments.length; i++) {
		var element = arguments[i];

		if (typeof element == 'string')
			element = document.getElementById(element) || undefined;

		if (arguments.length == 1)
			return element;

		elements.push( element );
	}

	return elements;
}

function _l(l) { location.href = l + location.search; }

function map (func, list) {
        var ret = [];
        for (var i = 0; i < list.length; i++) ret.push(func(list[i]));
        return ret;
}

function grep (func, list) {
	var ret = [];
	for (var i = 0; i < list.length; i++) if(func(list[i])) ret.push(list[i]);
	return ret;
}

function getSelectedItems(tree) {
        var start = new Object();
        var end = new Object();
        var numRanges = tree.view.selection.getRangeCount();
                        
        var itemList = [];
        for (var t=0; t<numRanges; t++){
                tree.view.selection.getRangeAt(t,start,end);
                for (var v=start.value; v<=end.value; v++){
                        itemList.push( tree.getElementsByTagName('treeitem')[v]);
                }       
        }               
                
        return itemList;
}

function findAncestor (node, name) {
        if (node.nodeName == name) return node;
        if (!node.parentNode) return null;
        return findAncestor(node.parentNode, name);
}       

function findAncestorStack (node, name, stack) {
        if (node.nodeName == name) stack.push(node);
        if (!node.parentNode) return null;
        findAncestorStack(node.parentNode, name, stack);
}               

function filterByAttribute(nodes,attrN,attrV) {
        var aResponse = [];
        for ( var i = 0; i < nodes.length; i++ ) {
                if ( nodes[i].getAttribute(attrN) == attrV ) aResponse.push(nodes[i]);
        }               
        return aResponse;
}       

function filterByAttributeNS(nodes,ns,attrN,attrV) {
        var aResponse = [];
        for ( var i = 0; i < nodes.length; i++ ) {
                if ( nodes[i].getAttributeNS(ns,attrN) == attrV ) aResponse.push(nodes[i]);
        }
        return aResponse;
}

function getKeys (hash) {
        var k = [];
        for (var i in hash) k.push(i);
        return k;
}


