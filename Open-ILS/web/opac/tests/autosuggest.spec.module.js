import { FieldCache, ListBoxCombobox, XmlFetcher } from '../../js/ui/default/opac/autosuggest.module.js';
import { JSDOM } from '../deps/node_modules/jsdom/lib/api.js';

function mockGlobals() {
    global.window = new JSDOM(`<!DOCTYPE html><form><input id="search" data-instructions="Press down arrow for autocomplete"></input></form>`).window;
    global.document = global.window.document;
    global.fetch = () => {
        return Promise.resolve(
            new Response('<as><val term="Concerto, harpsichord" field="5">Concerto, <span class=\'oils_AS\'>harpsichord</span></val><val term="Cambridge music handbooks" field="32">Cambridge music <span class=\'oils_AS\'>handbooks</span></val></as>', { status: 200, statusText: 'OK', })
        );
    };
    global.CustomEvent = class {};
}

function sleep(milliseconds) {
    return new Promise(resolve => setTimeout(resolve, milliseconds));
}

const mockFieldCache = {
    get: async (id) => {
        switch (id) {
            case 5:
                return Promise.resolve({
                    "label": "Uniform Title",
                    "name": "uniform",
                    "field_class": "title",
                    "id": 5,
                    "class_label": "Title"
                });
            case 32:
                return Promise.resolve({
                    "id": 32,
                    "field_class": "series",
                    "name": "browse",
                    "label": "Series Title (Browse)",
                    "class_label": "Title"
                });
        }
    }
};

describe('XmlFetcher', () => {
    it('creates a valid URL', () => {
        const fetcher = new XmlFetcher('dogs', 'subject', 1);
        expect(fetcher.url).toBe('/opac/extras/autosuggest?search_class=subject&limit=10&org_unit=1&query=dogs');
    });
    describe('#fetchSuggestions', () => {
        it('creates an array of Suggestion objects', async () => {
            mockGlobals();
            const fetcher = new XmlFetcher('ha', '', 1);
            const results = await fetcher.fetchSuggestions();
            expect(results.length).toBe(2);
            expect(results[0].term).toBe('Concerto, harpsichord');
            expect(results[0].searchClass).toBe(5);
            expect(results[1].highlighted).toBe('Cambridge music <span class="oils_AS">handbooks</span>');
        });
    });
});

describe('ListBoxComponent', () => {
    describe('#attach', () => {
        it('adds the attributes from the ARIA standard to the input', () => {
            global.document =  new JSDOM(`<!DOCTYPE html><input id="search"></input>`).window.document;
            new ListBoxCombobox('search', mockFieldCache).attach();
            const input = global.document.getElementById('search');
            expect(input.getAttribute('role')).toBe('combobox');
            expect(input.getAttribute('aria-autocomplete')).toBe('list');
            expect(input.getAttribute('aria-expanded')).toBe('false');
            expect(input.getAttribute('aria-controls')).toBe('search-autosuggest-listbox');
        });
        it('turns off the browser autocomplete', () => {
            global.document =  new JSDOM(`<!DOCTYPE html><input id="search"></input>`).window.document;
            new ListBoxCombobox('search', mockFieldCache).attach();
            const input = global.document.getElementById('search');
            expect(input.getAttribute('autocomplete')).toBe('off');
        });
        describe('when instruction text available', () => {
            it('creates an empty aria-live region, to be filled later', () => {
                global.document =  new JSDOM(`<!DOCTYPE html><input id="search" data-instructions="Press down arrow for autocomplete"></input>`).window.document;
                new ListBoxCombobox('search', mockFieldCache).attach();
                const ariaLiveRegion = global.document.getElementById('search-instructions-live-region');
                expect(ariaLiveRegion.getAttribute('aria-live')).toBe('polite');
                expect(ariaLiveRegion.textContent).toBe('');
            });
        });
    });
    describe('input event listeners', () => {
        describe('when the grid is closed', () => {
            it('adding text to the input displays the grid', async () => {
                mockGlobals();
                const combobox = new ListBoxCombobox('search', mockFieldCache);
                combobox.attach();
                const input = global.document.getElementById('search');
                input.value = 'ha';
                input.dispatchEvent(new global.window.Event('input'));
                await sleep(210);
                expect(global.document.getElementById('search-autosuggest-listbox').getAttribute('role')).toBe('listbox');
                expect(global.document.getElementById('search-autosuggest-listbox-0').getAttribute('role')).toBe('option');
                expect(global.document.getElementById('search-autosuggest-listbox-0-class').getAttribute('role')).toBe('note');
                expect(global.document.getElementById('search-autosuggest-listbox-0-term').textContent).toBe('Concerto, harpsichord');
                expect(global.document.getElementById('search-autosuggest-listbox-0-class').textContent).toBe('Title');
            });
            it('opening the grid adds any provided instructions to the live region', async () => {
                mockGlobals();
                const combobox = new ListBoxCombobox('search', mockFieldCache);
                combobox.attach();
                await combobox.displaySuggestions();
                await sleep(1200);
                expect(combobox.instructionsLiveRegion.textContent).toBe('Press down arrow for autocomplete');
            });
        });
        describe('when the grid is open', () => {
            it('pressing the down arrow focuses the first element of the grid',  async () => {
                mockGlobals();
                const input = global.document.getElementById('search');
                input.focus();
                input.value = 'dogs';

                const combobox = new ListBoxCombobox('search', mockFieldCache);
                combobox.attach();
                await combobox.displaySuggestions();
                const event = new global.window.KeyboardEvent('keyup', { 'key': 'ArrowDown', 'bubbles': true});
                await input.dispatchEvent(event);

                expect(global.document.getElementById('search-autosuggest-listbox-0')).toHaveClass('active');
                expect(input.getAttribute('aria-activedescendant')).toBe('search-autosuggest-listbox-0');
                expect(global.document.activeElement.id).toBe('search'); // DOM focus remains on the input
            });
            describe('when first row is focused', () => {
                it('pressing the down arrow focuses the second row', async () => {
                    mockGlobals();
                    const combobox = new ListBoxCombobox('search', mockFieldCache);
                    combobox.attach();
                    await combobox.displaySuggestions();
                    const input = global.document.getElementById('search');
                    const event = new global.window.KeyboardEvent('keyup', { 'key': 'ArrowDown', 'bubbles': true});

                    await input.dispatchEvent(event);
                    expect(global.document.getElementById('search-autosuggest-listbox-0')).toHaveClass('active');
                    expect(input.getAttribute('aria-activedescendant')).toBe('search-autosuggest-listbox-0');

                    await input.dispatchEvent(event);
                    expect(global.document.getElementById('search-autosuggest-listbox-1')).toHaveClass('active');
                    expect(input.getAttribute('aria-activedescendant')).toBe('search-autosuggest-listbox-1');
                });
            });
            it('emptying the input closes the grid',  async () => {
                mockGlobals();
                const combobox = new ListBoxCombobox('search', mockFieldCache);
                combobox.attach();
                await combobox.displaySuggestions();
                const input = global.document.getElementById('search');
                expect(input.getAttribute('aria-expanded')).toBe('true');
                input.value = '';
                input.dispatchEvent(new global.window.Event('input'));
                expect(input.getAttribute('aria-expanded')).toBe('false');
                expect(global.document.getElementById('search-autosuggest-listbox').innerHTML).toBe('');
            });
            it('pressing the Escape key while the input is focused closes the grid',  async () => {
                mockGlobals();
                const combobox = new ListBoxCombobox('search', mockFieldCache);
                combobox.attach();
                await combobox.displaySuggestions();
                const input = global.document.getElementById('search');
                expect(input.getAttribute('aria-expanded')).toBe('true');
                input.value = 'dog';
                const event = new global.window.KeyboardEvent('keyup', { 'key': 'Escape', 'bubbles': true});
                input.dispatchEvent(event);
                expect(input.getAttribute('aria-expanded')).toBe('false');
                expect(global.document.getElementById('search-autosuggest-listbox').innerHTML).toBe('');
            });
            it('pressing the Escape key while the listbox is focused closes the grid',  async () => {
                mockGlobals();
                const combobox = new ListBoxCombobox('search', mockFieldCache);
                combobox.attach();
                await combobox.displaySuggestions();
                const input = global.document.getElementById('search');
                expect(input.getAttribute('aria-expanded')).toBe('true');
                input.value = 'dog';
                const event = new global.window.KeyboardEvent('keyup', { 'key': 'Escape', 'bubbles': true});
                global.document.getElementById('search-autosuggest-listbox').dispatchEvent(event);
                expect(input.getAttribute('aria-expanded')).toBe('false');
                expect(global.document.getElementById('search-autosuggest-listbox').innerHTML).toBe('');
            });
            it('moving focus away from an open listbox\'s input closes the listbox',  async () => {
                mockGlobals();
                const combobox = new ListBoxCombobox('search', mockFieldCache);
                combobox.attach();
                await combobox.displaySuggestions();
                const input = global.document.getElementById('search');
                expect(input.getAttribute('aria-expanded')).toBe('true');
                input.dispatchEvent(new global.window.Event('blur'));
                expect(input.getAttribute('aria-expanded')).toBe('false');
                expect(global.document.getElementById('search-autosuggest-listbox').innerHTML).toBe('');
            });
            it('focusing an option then pressing enter chooses the term, dismisses the listbox, and submits the form', async () => {
                mockGlobals();
                const combobox = new ListBoxCombobox('search', mockFieldCache);
                combobox.attach();
                await combobox.displaySuggestions();
                const input = global.document.getElementById('search');
                input.value = 'cats';
                const form = global.document.querySelector('form');
                spyOn(form, 'submit');

                combobox.setFocus(1);
                const event = new global.window.KeyboardEvent('keyup', { 'key': 'Enter', 'bubbles': true});
                global.document.getElementById('search').dispatchEvent(event);

                expect(input.value).toBe('Cambridge music handbooks');
                expect(global.document.getElementById('search-autosuggest-listbox').innerHTML).toBe('');
                expect(form.submit).toHaveBeenCalled();
            });
            it('supplying search, then pressing enter without choosing a suggestion submits the form without error', async () => {
                mockGlobals();
                const combobox = new ListBoxCombobox('search', mockFieldCache);
                combobox.attach();
                await combobox.displaySuggestions();
                const input = global.document.getElementById('search');
                input.value = 'cats';
                const form = global.document.querySelector('form');
                spyOn(form, 'submit');

                const event = new global.window.KeyboardEvent('keyup', { 'key': 'Enter', 'bubbles': true});
                global.document.getElementById('search').dispatchEvent(event);

                expect(input.value).toBe('cats');
                expect(global.document.getElementById('search-autosuggest-listbox').innerHTML).toBe('');
                expect(form.submit).toHaveBeenCalled();
            });
            ['#search-autosuggest-listbox-1', '#search-autosuggest-listbox-1-term',
             '#search-autosuggest-listbox-1-term .oils_AS',
             '#search-autosuggest-listbox-1-class'].forEach((selector) => {
                it('clicking anywhere in an option chooses the term, dismisses the listbox, and submits the form', async () => {
                    mockGlobals();
                    const combobox = new ListBoxCombobox('search', mockFieldCache);
                    combobox.attach();
                    await combobox.displaySuggestions();
                    const input = global.document.getElementById('search');
                    input.value = 'cats';
                    const form = global.document.querySelector('form');
                    spyOn(form, 'submit');

                    const event = new global.window.KeyboardEvent('mousedown', { 'bubbles': true});
                    global.document.querySelector(selector).dispatchEvent(event);

                    expect(input.value).toBe('Cambridge music handbooks');
                    expect(global.document.getElementById('search-autosuggest-listbox').innerHTML).toBe('');
                    expect(form.submit).toHaveBeenCalled();
                });
            });
        });
    });
});

describe('FieldCache', () => {
    describe('#get', () => {
        it('returns an array of cmf data', async () => {
            mockGlobals();
            const cache = new FieldCache();
            cache.cmfCache = [
                {
                    "label": "Abbreviated Title",
                    "field_class": "title",
                    "name": "abbreviated",
                    "id": 2,
                    "class_label": "Title"
                }, {
                    "name": "corporate",
                    "field_class": "author",
                    "label": "Corporate Author",
                    "id": 7,
                    "class_label": "Author"
                }
            ];
            cache.cmcCache = [
                {
                    "label": "Title",
                    "name": "title"
                }
            ];
            expect(await cache.get(7)).toEqual({
                "name": "corporate",
                "field_class": "author",
                "label": "Corporate Author",
                "id": 7,
                "class_label": "Author"
            });
        });
    });
});
