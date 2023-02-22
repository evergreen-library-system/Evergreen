import {PageObjectModel} from 'nightwatch';

const authority: PageObjectModel = {
    elements: {
        searchTermInput: {
            selector: 'input[placeholder="Search Term"]'
        },
        authorityTypeInput: {
            selector: '//div[@class = "input-group"]/eg-combobox//input',
            locateStrategy: 'xpath'
        },
        subjectAuthorityType: {
            selector: '//button/span[text() = "Subject"]',
            locateStrategy: 'xpath'
        },
        searchResult: {
            selector: '//a[contains(text(), "Philosophy, Chinese")]',
            locateStrategy: 'xpath'
        },
        editTab: {
            selector: '//a[text()="Edit" and contains(@class, "nav-link")]',
            locateStrategy: 'xpath'
        }
    }
};

export default authority;
