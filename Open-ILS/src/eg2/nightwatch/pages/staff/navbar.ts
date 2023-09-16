import {PageObjectModel} from 'nightwatch';

const navBar: PageObjectModel = {
    elements: {
        acqMenu: {
            selector: '//button[@class = "dropdown-toggle nav-link" and contains(text(), "Acquisitions")]',
            locateStrategy: 'xpath'
        },
        catMenu: {
            selector: '//button[@class = "dropdown-toggle nav-link" and contains(text(), "Cataloging")]',
            locateStrategy: 'xpath'
        },
        catMenuMarcBatchImportExport: {
            selector: 'a[href="/eg2/en-US/staff/cat/vandelay/import"]'
        },
        searchMenu: {
            selector: '//button[@class = "dropdown-toggle nav-link" and contains(text(), "Search")]',
            locateStrategy: 'xpath'
        }
    }
};

export default navBar;
