import {PageObjectModel} from 'nightwatch';

const catalogSearch: PageObjectModel = {
    elements: {
        searchPreferencesButton: {
            selector: '//a[text() = "Search Preferences"]',
            locateStrategy: 'xpath'
        }
    }
};

export default catalogSearch;
