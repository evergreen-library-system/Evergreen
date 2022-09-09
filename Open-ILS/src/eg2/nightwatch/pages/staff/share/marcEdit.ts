import {PageObjectModel} from 'nightwatch';

// Create a bunch of selectors for all the MARC tags
let marcElements = {};
// An array of 010-999
const marcTags = [...Array(990).keys()].map((x: number) => (x + 10).toString().padStart(3, '0'));
for (const tag of marcTags) {
    marcElements['marcTag' + tag] = {
        selector: '//input[text() = "' + tag + '" and @aria-label = "Data Field Tag"]',
        locateStrategy: 'xpath'
    };
}


const marcEditPage: PageObjectModel = {
    elements: {
        ...marcElements,
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