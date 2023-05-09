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
        marcEdit.waitForElementVisible('@marcTag450', 15_000)
                .setValue('@marcTag450', '550')
                .click('@saveChangesButton')
                .assert.visible('#eg-toast-container')
                .setValue('@marcTag550', '450')
                .click('@saveChangesButton');
    }
};
