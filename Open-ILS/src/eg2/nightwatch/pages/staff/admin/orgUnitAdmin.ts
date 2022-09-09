import {PageObjectModel} from 'nightwatch';

const orgUnitAdmin: PageObjectModel = {
    elements: {
        system2expand: {
            selector: '//div[@class = "eg-tree"]/div[./div/a[text()="Example System 2 -- SYS2"]]/div[@class="eg-tree-node-expandy"]/div/span[text()="expand_more"]',
            locateStrategy: 'xpath'
        },
        br3: {
            selector: '//a[text()="Example Branch 3 -- BR3"]',
            locateStrategy: 'xpath'
        },
        saveButton: {
            selector: '//button[text()="Save"]',
            locateStrategy: 'xpath'
        }
    }
};

export default orgUnitAdmin;
