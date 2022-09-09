import {EnhancedPageObject, NightwatchBrowser} from 'nightwatch';
import {fixtureFile, randomString} from '../../utils';

const exampleXpath = '//*[@tag="010"]/*[@code="a"][1]';

function navigateToMarcBatchImport(vandelay: EnhancedPageObject): void {
    browser.page.navbar().click('@catMenu')
                         .click('@catMenuMarcBatchImportExport')
                         .verify.textContains('div.lead.alert', 'MARC Batch Import/Export');
}

module.exports = {
    before: (browser: NightwatchBrowser) => {
        // TODO: Once https://bugs.launchpad.net/evergreen/+bug/1989260 is resolved,
        // login as a cataloging administrator, rather than the admin / demo123 credentials
        browser.page.login().loginToWebClient(browser, 'admin', 'demo123');
    },

    after: (browser: NightwatchBrowser) => {
        browser.end();
    },

    'Can create a new record display attribute': (browser: NightwatchBrowser) => {
        const vandelay = browser.page.vandelay();
        navigateToMarcBatchImport(vandelay);
        vandelay.click('@recordDisplayAttributes')
                .click('#authority')
                .click('@newVqradButton')
                .setValue('@codeInput', 'lccn')
                .setValue('@descriptionInput', 'LC control number')
                .setValue('@xpathInput', exampleXpath)
                .click('@saveButton')
                .assert.textContains('div.eg-grid-body', exampleXpath);
    },

    'Record display attribute displays in queue screen': (browser: NightwatchBrowser) => {
        const vandelay = browser.page.vandelay();
        navigateToMarcBatchImport(vandelay);
            vandelay.click('@recordTypeCombobox') // open the combobox
                    .click('@authorityRecordType') // select the option we want
                    .setValue('@queueName', randomString())
                    .setValue('#upload-file', fixtureFile('authority-record.mrc'))
                    .click('@uploadButton')
                    .waitForElementVisible('@goToQueueButton', 10_000)
                    .click('@goToQueueButton')
                    .assert.textContains('div.eg-grid-header-row', 'LC control number')
                    .assert.textContains('div.eg-grid-body', 'sh 85038796');
    }
};
