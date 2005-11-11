var stpicopen	= '../../../images/slimtree/folder.gif';
var stpicclose = '../../../images/slimtree/folderopen.gif';
var stpicblank = '../../../images/slimtree/page.gif';
var stpicline	= '../../../images/slimtree/line.gif';
var stpicjoin	= '../../../images/slimtree/join.gif';
var stpicjoinb = '../../../images/slimtree/joinbottom.gif';

var stimgopen	= elem('img',{src:stpicopen,border:0});
var stimgclose	= elem('img',{src:stpicclose,border:0});
var stimgblank	= elem('img',{src:stpicblank,border:0});
var stimgline	= elem('img',{src:stpicline,border:0});
var stimgjoin	= elem('img',{src:stpicjoin,border:0, style:'display:inline;'});

function SlimTree(context) { this.context = context; }

SlimTree.prototype.addNode = function( id, pid, name, action ) {

	var div			= elem('div',{id:id});
	var topdiv		= elem('div',{style:'vertical-align:middle'});
	var link			= elem('a', {id:'stlink_' + id}); 
	var actionref	= elem('a',{href:action}, name);
	var contdiv		= elem('div',{id:'stcont_' + id});

	topdiv.appendChild(link);
	topdiv.appendChild(actionref);
	div.appendChild(topdiv);
	div.appendChild(contdiv);

	if( pid == -1 ) { 
		this.rootid = id;
		this.context.appendChild(div);
		link.appendChild(stimgblank.cloneNode(true));
	} else {
		if(pid == this.rootid) stOpen(pid);
		else stClose(pid);
		getId(pid).setAttribute('haschild','1');
		link.appendChild(stimgblank.cloneNode(true));
		div.style.paddingLeft = '18px';
		div.style.backgroundImage = 'url('+stpicjoinb+')';
		div.style.backgroundRepeat = 'no-repeat';
		getId('stcont_' + pid).appendChild(div);
		if (div.previousSibling) {
			div.previousSibling.firstChild.appendChild(stimgjoin.cloneNode(true));
			div.previousSibling.firstChild.appendChild(div.previousSibling.firstChild.firstChild);
			div.previousSibling.firstChild.appendChild(div.previousSibling.firstChild.firstChild);
			div.previousSibling.firstChild.firstChild.style.marginLeft = '-18px';

			div.previousSibling.style.backgroundImage = 'url('+stpicline+')';
			div.previousSibling.style.backgroundRepeat = 'repeat-y';
		}
	}
}

SlimTree.prototype.expandAll = function() { stFlex(this.rootid, 'open'); }
SlimTree.prototype.closeAll = function() { stFlex(this.rootid,'close', this.rootid); }
function stFlex(id, type, root) {
	if(type=='open') stOpen(id);
	else { if (id != root) stClose(id); }
	var n = getId('stcont_' + id);
	for( var c = 0; c != n.childNodes.length; c++ ) {
		var ch = n.childNodes[c];
		if(ch.nodeName.toLowerCase() == 'div') {
			if(getId(ch.id).getAttribute('haschild') == '1') 
				stFlex(ch.id, type);
		}
	}
}

function stOpen( id ) {
	var link = getId('stlink_' + id);
	removeChildren(link);
	link.appendChild(stimgclose.cloneNode(true));
	link.setAttribute('href','javascript:stClose("'+id+'");');
	unHideMe(getId('stcont_' + id));
}

function stClose( id ) {
	var link = getId('stlink_' + id);
	removeChildren(link);
	link.appendChild(stimgopen.cloneNode(true));
	link.setAttribute('href','javascript:stOpen("'+id+'");');
	hideMe(getId('stcont_' + id));
}

