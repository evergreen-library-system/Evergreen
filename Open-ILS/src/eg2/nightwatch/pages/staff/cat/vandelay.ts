import {PageObjectModel} from 'nightwatch';
import {fmEditorFieldSelector} from '../../../src/utils';

const vandelay: PageObjectModel = {
    elements: {
        recordDisplayAttributes: {
            selector: '//a[text()="Record Display Attributes"]',
            locateStrategy: 'xpath'
        },
        newVqradButton: {
            selector: '//button[not(@disabled) and contains(text(), "New Queued Authority Record Attribute Definition")]',
            locateStrategy: 'xpath'
        },
        descriptionInput: {
            selector: fmEditorFieldSelector('Description')
        },
        saveButton: {
            selector: '//button[text()="Save"]',
            locateStrategy: 'xpath'
        },
        recordTypeCombobox: {
            selector: fmEditorFieldSelector('Record Type')
        },
        queueName: {
            selector: fmEditorFieldSelector('Select or Create a Queue')
        },
        uploadButton: {
            selector: '//button[text()="Upload"]',
            locateStrategy: 'xpath'
        },
        goToQueueButton: {
            selector: '//button[text()="Go To Queue"]',
            locateStrategy: 'xpath'
        },
        authorityRecordType: {
            selector: '//button/span[text()="Authority Records"]',
            locateStrategy: 'xpath'
        },
        authorityAttributesTab: {
            selector: '//a[text()="Authority Attributes" and contains(@class, "nav-link")]',
            locateStrategy: 'xpath'
        }
    }
};

export default vandelay;
