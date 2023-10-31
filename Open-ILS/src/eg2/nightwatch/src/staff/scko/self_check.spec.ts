import {NightwatchBrowser} from 'nightwatch';

module.exports = {
    before: (browser: NightwatchBrowser) => {
        browser.page.login().loginToWebClient(browser, 'admin', 'demo123');
    },

    after: (browser: NightwatchBrowser) => {
        browser.end();
    },

    'Axe finds no accessibility issues on login screen': (browser: NightwatchBrowser) => {
        browser.navigateTo('/eg2/en-US/staff/scko')
               .assert.elementPresent('#staff-username')
               .axeInject().axeRun();
    },


};
