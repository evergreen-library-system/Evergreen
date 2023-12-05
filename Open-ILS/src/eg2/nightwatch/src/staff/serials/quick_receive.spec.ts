import {NightwatchBrowser} from 'nightwatch';

module.exports = {
    before: (browser: NightwatchBrowser) => {
        browser.page.login().loginToWebClient(browser, 'admin', 'demo123');
    },

    after: (browser: NightwatchBrowser) => {
        browser.end();
    },

    'Can receive a serial item': (browser: NightwatchBrowser) => {
        // Set up an expected special item
        browser.navigateTo('/eg2/en-US/staff/catalog/record/237')
            .click('#actionsForSerials')
            .click('xpath', '//a[contains(text(), "Manage Subscriptions")]')
            .click('xpath', '//button[contains(text(), "New Subscription")]')
            .setValue('div[ng-model="ssub.start_date"] input', '2020-01-01')
            .setValue('input[ng-model="sdist.label"]', 'My Label')
            .click('xpath', '//button[contains(text(), "Save")]')
            .click('xpath', '//a[contains(text(), "Manage Issues")]')
            .click('xpath', '//button[contains(text(), "Add Special Issue")]')
            .click('input[value="Save"]');

        // Receive the item in Quick Receive
        browser.navigateTo('/eg2/en-US/staff/catalog/record/237')
            .click('#actionsForSerials')
            .click('xpath', '//a[contains(text(), "Quick Receive")]')
            .click('xpath', '//button[contains(text(), "Continue")]')
            .click('xpath', '//button[contains(text(), "Receive")]')
            .assert.visible('#eg-toast-container')
            .assert.textContains('#eg-toast-container', 'Items received');
    }
};
