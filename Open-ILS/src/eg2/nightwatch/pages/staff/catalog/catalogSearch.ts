import {PageObjectModel} from 'nightwatch';

const catalogSearch: PageObjectModel = {
    elements: {
        searchPreferencesButton: {
            selector: '//button[text() = "Search Preferences"]',
            locateStrategy: 'xpath'
        }
    }
};

export default catalogSearch;
