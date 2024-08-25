import {NightwatchBrowser} from 'nightwatch';

module.exports = {
    before: (browser: NightwatchBrowser) => {
        // log in as circ admin
        browser.page.login().loginToWebClient(browser, 'br3kwright', 'demo123');
        browser.navigateTo('eg2/en-US/staff/admin/booking/resource')
    },

    'Form is accessible': (browser: NightwatchBrowser) => {
            browser.click('xpath', '//button[contains(text(), "New Resource")]')
                   .axeInject().axeRun('form');
    },
};
