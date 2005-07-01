sdump('D_TRACE','Loading clam_shell.js\n');

function clam_shell_init(p) {
	dump("TESTING: clam_shell.js: " + mw.G['main_test_variable'] + '\n');
	if (p) {
		if (p.horizontal) {
			get_widget(p.w.document,p.clamshell).orient = 'horizontal';
		} else if (p.vertical) {
			get_widget(p.w.document,p.clamshell).orient = 'vertical';
		}
	}
	var nl = get_widget(p.w.document,p.clamshell).getElementsByTagName('deck');
	var first_deck = nl[0];
	var second_deck = nl[1];

	p.w.first_deck = first_deck;
	p.w.second_deck = second_deck;
	p.w.get_card_in_first_deck = function (idx) {
		if (idx)
			return first_deck.childNodes[ idx ];
		else
			return first_deck.selectedPanel;
	}
	p.w.get_card_in_second_deck = function (idx) {
		if (idx)
			return second_deck.childNodes[ idx ];
		else
			return second_deck.selectedPanel;
	}
	p.w.set_first_deck = function (idx) { return set_deck(p.w.document,first_deck,idx); };
	p.w.set_second_deck = function (idx) { return set_deck(p.w.document,second_deck,idx); };
	p.w.replace_card_in_first_deck = function (idx,chrome,params) {
		return replace_card_in_deck(p.w.document,first_deck,idx,chrome,params);
	};
	p.w.replace_card_in_second_deck = function (idx,chrome,params) {
		return replace_card_in_deck(p.w.document,second_deck,idx,chrome,params);
	};
	p.w.new_card_in_first_deck = function (chrome,params) {
		return new_card_in_deck(p.w.document,first_deck,chrome,params);
	};
	p.w.new_card_in_second_deck = function (chrome,params) {
		return new_card_in_deck(p.w.document,second_deck,chrome,params);
	};

	if (p.onload) {
		try {
			dump('D_TRACE','trying psuedo-onload...\n');
			p.onload(p.w);
		} catch(E) {
			dump( js2JSON(E) + '\n' );
		}
	}

}

function new_card_in_deck(doc,deck,chrome,params) {
	deck = get_widget(doc,deck);
	var new_card = document.createElement('iframe');
	deck.appendChild(new_card);
	new_card.setAttribute('flex','1');
	new_card.setAttribute('src',chrome);
	new_card.setAttribute('id','card_'+(deck.childNodes.length-1));
	return new_card.contentWindow;
}

function replace_card_in_deck(doc,deck,idx,chrome,params) {
	deck = get_widget(doc,deck);
	var old_card = deck.childNodes[ idx ];
	var new_card = document.createElement('iframe');
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
