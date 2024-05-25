import {NightwatchBrowser} from 'nightwatch';
import {navigateToEgUrl} from '../../utils';

module.exports = {
    before: (browser: NightwatchBrowser) => {
        browser.page.login().loginToWebClient(browser, 'admin', 'demo123');
    },

    after: (browser: NightwatchBrowser) => {
        browser.end();
    },

    'Can modify an authority record': (browser: NightwatchBrowser) => {
        navigateToEgUrl('/eg2/en-US/staff/cat/authority/browse', browser);
        const authority = browser.page.authority();
        authority.setValue('@searchTermInput', 'Philosophy')
                 .click('@authorityTypeInput')
                 .click('@subjectAuthorityType')
                 .click('@searchResult')
                 .click('@editTab');
        const marcEdit = browser.page.marcEdit();
        browser.waitForElementVisible('eg-marc-editor', 15_000);
        browser.execute(() => {
            Array.from(document.querySelectorAll('input')).find((field) => field.value === "450").value = "550";
        });

        marcEdit.click('@saveChangesButton')
                .assert.visible('#eg-toast-container');

        browser.execute(() => {
            Array.from(document.querySelectorAll('input')).find((field) => field.value === "450").value = "550";
        });
        marcEdit.click('@saveChangesButton');
    },
    'Authority browse screen passes axe accessibility checks': (browser: NightwatchBrowser) => {
        navigateToEgUrl('/eg2/en-US/staff/cat/authority/browse', browser);
        browser.waitForElementVisible('h1');
        browser.axeInject().axeRun();
    }
};
