import {NightwatchBrowser} from 'nightwatch';
import { openTab, waitForTabCount } from '../../utils';

module.exports = {
    before: (browser: NightwatchBrowser) => {
        browser.page.login().loginToWebClient(browser, 'admin', 'demo123');
    },

    after: (browser: NightwatchBrowser) => {
        browser.end();
    },

    'Can set a default item alert type on the server': (browser: NightwatchBrowser) => {
        browser.navigateTo('eg2/en-US/staff/catalog/record/223')
               .click('xpath', '//button[contains(text(), "Add Holdings")]');

        waitForTabCount(2, browser);
        openTab(1, browser);

        browser.click('xpath', '//a[text() = "Preferences"]')
               .setValue('#default-item-alert-type', 'checkin of missing');
         // Click the first result
        browser.click('ngb-typeahead-window button span');

         // Verify that the setting is persisted in the database
        browser.navigateTo('eg/staff/admin/workstation/stored_prefs')
               .click('xpath', "//a[contains(text(), 'Server Workstation Prefs')]")
               .click('xpath', "//a[text() = 'eg.cat.volcopy.defaults']")
               .assert.textContains('pre', '"item_alert_type": 5');
    },

    'Default item alert type is selected when creating a new alert': (browser: NightwatchBrowser) => {
        browser.navigateTo('eg2/en-US/staff/catalog/record/223')
               .click('xpath', '//button[contains(text(), "Add Holdings")]');

        waitForTabCount(3, browser);
        openTab(2, browser);

        browser.click('xpath', '//a[text() = "Item Attributes"]')
               .click('xpath', '//button[contains(text(), "Item Alerts")]')
               .assert.valueEquals('#item-alert-type', 'Checkin of missing copy');
    },

    'Can unset the default item alert type': (browser: NightwatchBrowser) => {
        browser.navigateTo('eg2/en-US/staff/catalog/record/223')
               .click('xpath', '//button[contains(text(), "Add Holdings")]');

        waitForTabCount(4, browser);
        openTab(3, browser);

        browser.click('xpath', '//a[text() = "Preferences"]')
               .assert.valueEquals('#default-item-alert-type', 'Checkin of missing copy')
               .execute(() => {
                    const field = document.getElementById('default-item-alert-type') as HTMLInputElement;
                    field.select();
               })
               .sendKeys('#default-item-alert-type', browser.Keys.BACK_SPACE)
               .click('#statcat_filter');

       // Verify that the setting is no longer persisted in the database
        browser.navigateTo('eg/staff/admin/workstation/stored_prefs')
               .click('xpath', "//a[contains(text(), 'Server Workstation Prefs')]")
               .click('xpath', "//a[text() = 'eg.cat.volcopy.defaults']")
               .assert.not.textContains('pre', '"item_alert_type"');

    },

    'Config screen has no obvious accessibility issues': (browser: NightwatchBrowser) => {
        browser.navigateTo('eg2/en-US/staff/catalog/record/223')
               .click('xpath', '//button[contains(text(), "Add Holdings")]');

        waitForTabCount(5, browser);
        openTab(4, browser);
        browser.click('xpath', '//a[text() = "Preferences"]')
               .axeInject()
               .axeRun('body', {rules: { 'color-contrast': { enabled: false }}});
    }

}
