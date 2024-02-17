/* An autosuggest that uses the
 * ARIA Authoring Practices Guide
 * "Combobox with listbox popup" pattern
 * (https://www.w3.org/WAI/ARIA/apg/patterns/combobox/)
 */
import { Debouncer } from "./debouncer.module.js";

export class XmlFetcher {
  constructor(query, searchClass, orgUnit) {
    this.url = '/opac/extras/autosuggest?search_class=' + searchClass +
               '&limit=10&org_unit=' + orgUnit + '&query=' + encodeURIComponent(query);
  }
  async fetchSuggestions() {
    const response = await fetch(this.url);
    const str = await response.text();
    const xmlResponse = new window.DOMParser().parseFromString(str, "text/xml");
    const xmlSuggestions = xmlResponse.evaluate(
      "//val",
      xmlResponse,
      null,
      0,
      null
    );
    let suggestions = [];
    let node = null;
    while ((node = xmlSuggestions.iterateNext())) {
      suggestions.push(new Suggestion(node));
    }
    return suggestions;
  }
}

export class Suggestion {
  constructor(node) {
    this.term = node.getAttribute('term');
    this.searchClass = parseInt(node.getAttribute('field'));
    this.highlighted = this.#decodeXMLEntities(node.innerHTML);
  }
  async asGridRow(rowPrefix, fieldCache) {
    const searchClassData = await fieldCache.get(this.searchClass);
    return '<li id="' + rowPrefix + '" class="list-group-item" role="option">' +
      '<span id="' + rowPrefix + '-term" tabindex="-1">' + this.highlighted + '</span> ' +
      '<span id="' + rowPrefix + '-class" tabindex="-1" role="note" class="float-right ml-3" data-class-name="' +
      searchClassData?.field_class + '">' + searchClassData?.class_label + '</span>' +
    '</li>';
  }
  #decodeXMLEntities(encoded) {
    const textArea = document.createElement("textarea");
    textArea.innerHTML = encoded;
    return textArea.value;
  }
}

export class FieldCache {
  constructor() {
    this.requestComplete = new CustomEvent('requestComplete');
    this.cacheReady = new CustomEvent('cacheReady');
    document.addEventListener('requestComplete', (() => {
      this.#handleRequestComplete();
    }));
  }
  get(cmfId) {
    if (this.#cacheIsPresent()) {
      return Promise.resolve(this.cmfCache.find(cmf => cmf.id === cmfId));
    } else {
      this.#setUpCache();
      return new Promise((resolve) => {
        document.addEventListener('cacheReady', () => {
          resolve(this.cmfCache.find(cmf => cmf.id === cmfId));
        }, {once: true});
      });
    }
  }
  #setUpCache() {
    const session = new OpenSRF.ClientSession('open-ils.fielder'); // eslint-disable-line no-undef
    session.request({
      method: 'open-ils.fielder.cmc.atomic',
      params: [{"query": {"name": {"!=": null}},
      fields: ["name", "label"]}],
      oncomplete: (resp) => {
        this.cmcCache = resp.recv()?.hash?.content;
        document.dispatchEvent(this.requestComplete);
      }}).send();
    session.request({
      method: 'open-ils.fielder.cmf.atomic',
      params: [{"query": {"id": {"!=": null}},
      fields: ["field_class", "id", "name", "label"]}],
      oncomplete: (resp) => {
        this.cmfCache = resp.recv()?.hash?.content;
        document.dispatchEvent(this.requestComplete);
      }}).send();
  }
  #cacheIsPresent() {
    return this.cmfCache?.length && this.cmcCache?.length;
  }
  #handleRequestComplete() {
    if (this.#cacheIsPresent()) {
      this.cmfCache.forEach((cmf) => {
        let cmc = this.cmcCache.find(cached => cached.name === cmf.field_class);
        cmf.class_label = cmc.label;
      });
      document.dispatchEvent(this.cacheReady);
    }
  }
}

export class ListBoxCombobox {

  #debouncedDisplaySuggestions;

  constructor(inputId, fieldCache = new FieldCache()) {
    this.inputId = inputId;
    this.input = document.getElementById(this.inputId);

    this.instructions = this.input.getAttribute('data-instructions');

    this.listboxId = inputId + '-autosuggest-listbox';
    this.listbox = document.createElement('ul');
    this.listbox.setAttribute('role', 'listbox');
    this.listbox.setAttribute('aria-label', this.input.getAttribute('data-listbox-name'));
    this.listbox.classList.add('list-group', 'position-absolute');
    this.listbox.id = this.listboxId;

    this.isOpen = false;
    this.currentRowNumber = null; // null meaning that no suggestion is currently selected
    this.#addEventListeners();
    this.fieldCache = fieldCache;

    // We only want a single instance of this generated function in the class, so that
    // the timer is shared between all its calls
    this.#debouncedDisplaySuggestions = new Debouncer().debounce(async () => { await this.displaySuggestions(); }, 200);
  }
  #addEventListeners() {
    this.#addContainerEventListeners();
    this.#addInputEventListeners();
    this.#addGridEventListeners();
  }
  #addContainerEventListeners() {
    this.input.parentElement.addEventListener('keyup', (event) => {
      switch(event.key) {
        case 'ArrowUp':
          this.handleUpArrow();
          break;
        case 'ArrowDown':
          this.handleDownArrow();
          break;
        case 'Esc': // Legacy support
        case 'Escape':
          this.#closeSuggestionsList();
          break;
        case 'Enter':
          event.preventDefault();
          this.#selectAndSubmit();
          break;
        case 'Backspace':
          this.listbox.querySelectorAll('*').forEach(element => element.classList.remove('active'));
          this.input.removeAttribute('aria-activedescendant');
          break;
      }
    });
    this.input.parentElement.addEventListener('keydown', (event) => {
      if (event.key === 'Enter') { event.preventDefault(); }
    });
  }
  #addInputEventListeners() {
    this.input.addEventListener('input', async () => {
      if (this.input?.value?.length) {
        this.#debouncedDisplaySuggestions();
      } else {
        this.#closeSuggestionsList();
      }
    });
    this.input.addEventListener('blur', async () => {
      if (this.isOpen) {
        this.currentRowNumber = null;
        this.#closeSuggestionsList();
      }
    });
  }
  #addGridEventListeners() {
    this.listbox.addEventListener('click', (event) => {
      this.setFocusById(event.target.closest('li').id);
      this.#selectAndSubmit();
    });

  }
  attach() {
    this.input.setAttribute('role', 'combobox');
    this.input.setAttribute('aria-autocomplete', 'list');
    this.input.setAttribute('aria-expanded', 'false');
    this.input.setAttribute('aria-controls', this.listboxId);
    this.input.setAttribute('autocomplete', 'off');
    this.input.after(this.listbox);

    if (this.instructions) {
      this.instructionsLiveRegion = document.createElement('span');
      this.instructionsLiveRegion.id = this.inputId + '-instructions-live-region';
      this.instructionsLiveRegion.setAttribute('aria-live', 'polite');
      this.instructionsLiveRegion.classList.add('sr-only', 'visually-hidden');
      this.listbox.after(this.instructionsLiveRegion);
    }
  }
  async displaySuggestions() {
    const qtype = document.getElementById('qtype')?.value || 'keyword';
    const org = this.input.getAttribute('data-search-org') || 1;
    const fetcher = new XmlFetcher(this.input.value, qtype, org);
    const results = await fetcher.fetchSuggestions();
    this.listboxEntries = await Promise.all(results.map(async (suggestion, index) => {
      return await suggestion.asGridRow(this.#rowId(index), this.fieldCache);
    }));
    this.listbox.innerHTML = this.listboxEntries.join('');
    if(this.listboxEntries.length) {
      this.#markAsOpen();
      if (this.instructions) {
        // Wait to set the aria-live region, so it doesn't compete with
        // other onchange screen reader announcments
        setTimeout(
          () => { this.instructionsLiveRegion.textContent = this.instructions; },
          1200
        );
      }
    }
    return;
  }

  handleUpArrow() {
    if (this.isOpen) {
      if (this.currentRowNumber === 0) {
        this.#closeSuggestionsList();
        this.currentRowNumber = null;
      } else if (this.currentRowNumber !== null) {
        this.setFocus(this.currentRowNumber - 1);
      } else {
        this.setFocus(0);
      }
    }
  }
  async handleDownArrow() {
    await this.#openIfNecessary();
    if (!this.isOpen) { return; }
    if (this.listboxEntries.length - 1 === this.currentRowNumber) { return; }
    if (this.currentRowNumber == null) {
      this.setFocus(0);
    } else {
      this.setFocus(this.currentRowNumber + 1);
    }
  }

  #openIfNecessary() {
    if (this.input?.value?.length && !this.isOpen) {
      return this.displaySuggestions();
    }
    return Promise.resolve();
  }

  #closeSuggestionsList() {
    this.isOpen = false;
    this.input.setAttribute('aria-expanded', false);
    this.listbox.replaceChildren();
  }
  #markAsOpen() {
    this.isOpen = true;
    this.input.setAttribute('aria-expanded', true);
  }
  #selectAndSubmit() {
    if (this.currentRowNumber !== null) {
      // munge search only if a suggestion is actually selected
      this.input.value = this.#currentSuggestionText();
      const qtype = document.getElementById('qtype');
      if (qtype) { qtype.value = this.#currentSearchClass(); }
    }
    this.input.closest('form').submit();
    this.#closeSuggestionsList();
  }
  setFocus(rowNumber) {
    this.currentRowNumber = rowNumber;
    const id = this.#rowId(rowNumber);
    this.listbox.querySelectorAll('*').forEach(element => element.classList.remove('active'));
    document.getElementById(id).classList.add('active');
    this.input.setAttribute('aria-activedescendant', id);
  }
  setFocusById(id) {
    const idMatcher = new RegExp(this.listboxId + '-(\\d+)(-\\w+)?');
    const coordinates = id.match(idMatcher);
    this.setFocus(coordinates[1]);
  }
  #rowId(rowNumber) {
    return this.listboxId + '-' + rowNumber;
  }
  #currentSuggestionText() {
    return document.getElementById(this.#rowId(this.currentRowNumber) + '-' + 'term').textContent;
  }
  #currentSearchClass() {
    return document.getElementById(this.#rowId(this.currentRowNumber) + '-' + 'class').getAttribute('data-class-name');
  }
}
