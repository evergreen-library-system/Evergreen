sdump('D_TRACE','Loading clam_shell.js\n');

function clam_shell_init(p) {
	sdump('D_CLAM',"TESTING: clam_shell.js: " + mw.G['main_test_variable'] + '\n');
	sdump('D_CONSTRUCTOR',arg_dump(arguments));

	if (p) {
		// This code breaks the splitter, so don't use
		if (p.horizontal) {
			sdump('D_CLAM','Setting horizontal\n');
			p.node.orient = 'horizontal';
		} else if (p.vertical) {
			sdump('D_CLAM','Setting vertical\n');
			p.node.orient = 'vertical';
		}

		p.splitter_node = p.node.childNodes[1];
		if (p.hide_splitter) {
			sdump('D_CLAM','Hiding splitter\n');
			p.splitter_node.hidden = true;
		} else {
			sdump('D_CLAM','Showing splitter\n');
			p.splitter_node.hidden = false;
		}
			
	}

	p.first_deck = p.node.firstChild;
	p.second_deck = p.node.lastChild;

	p.get_card_in_first_deck = function (idx) {
		if (idx)
			return first_deck.childNodes[ idx ];
		else
			return first_deck.selectedPanel;
	}

	p.get_card_in_second_deck = function (idx) {
		if (idx)
			return second_deck.childNodes[ idx ];
		else
			return second_deck.selectedPanel;
	}

	p.set_first_deck = function (idx) { return p.first_deck.selectedIndex = idx; };

	p.set_second_deck = function (idx) { return p.second_deck.selectedIndex = idx; };

	p.replace_card_in_first_deck = function (idx,chrome,params) {
		return replace_card_in_deck(p.first_deck,idx,chrome,params);
	};

	p.replace_card_in_second_deck = function (idx,chrome,params) {
		return replace_card_in_deck(p.second_deck,idx,chrome,params);
	};

	p.new_card_in_first_deck = function (chrome,params) {
		return new_card_in_deck(p.first_deck,chrome,params);
	};
	p.new_card_in_second_deck = function (chrome,params) {
		return new_card_in_deck(p.second_deck,chrome,params);
	};

	return p;
}

function new_card_in_deck(deck,chrome,params) {
	sdump('D_CLAM',arg_dump(arguments));
	var new_card = deck.ownerDocument.createElement('iframe');
	deck.appendChild(new_card);
	new_card.setAttribute('flex','1');
	new_card.setAttribute('src',chrome);
	new_card.setAttribute('id','card_'+(deck.childNodes.length-1));
	new_card.contentWindow.mw = mw;
	return new_card.contentWindow;
}

function replace_card_in_deck(deck,idx,chrome,params) {
	sdump('D_CLAM',arg_dump(arguments));
	var old_card = deck.childNodes[ idx ];
	var new_card = deck.ownerDocument.createElement('iframe');
	new_card.setAttribute('flex','1');
	new_card.setAttribute('src',chrome);
	deck.appendChild(new_card);
	deck.replaceChild(new_card,old_card);
	new_card.setAttribute('id','card_'+idx);
	new_card.contentWindow.mw = mw;
	if (params)
		new_card.contentWindow.params = params;
	return new_card.contentWindow;
}

