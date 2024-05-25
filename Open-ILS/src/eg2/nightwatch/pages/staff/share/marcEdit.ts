import {PageObjectModel} from 'nightwatch';

const marcEditPage: PageObjectModel = {
    elements: {
        dataFieldTag: {
            selector: 'input[aria-label = "Data Field Tag"]'
        },
        saveChangesButton: {
            selector: '//button[text() = "Save Changes"]',
            locateStrategy: 'xpath'
        }
    }
};

export default marcEditPage;
