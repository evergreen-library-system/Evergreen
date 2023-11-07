import {NightwatchBrowser} from 'nightwatch';

module.exports = {
    before: (browser: NightwatchBrowser) => {
        browser.page.login().loginToWebClient(browser, 'admin', 'demo123');
    },

    after: (browser: NightwatchBrowser) => {
        browser.end();
    },

    'Axe finds no accessibility issues on login screen': (browser: NightwatchBrowser) => {
        browser.navigateTo('/eg2/en-US/staff/selfcheck')
               .assert.elementPresent('#staff-username')
               .axeInject().axeRun();
    },

    'Can log in as a staff member to start the self check': (browser: NightwatchBrowser) => {
        browser.setValue('#staff-username', 'admin')
               .setValue('#staff-password', 'demo123')
               .click('xpath', '//button[contains(text(), "Sign In")]')
               .assert.textContains('main', 'Please log in with your username or library barcode',
               'We have logged in as a staff member, and now it prompts patrons to log in');
    },

    'Patron can check out an item': (browser: NightwatchBrowser) => {
        browser.setValue('#patron-username', '99999388575') // Patron Blake Davis from the concerto data set
               .submitForm('#patron-username')
               .assert.textContains('body', 'Please enter an item barcode')
               .setValue('#item-barcode', 'FIC400001583')
               .submitForm('#item-barcode')
               .assert.textContains('body', 'Checkout Succeeded');
    },

    'Patron can view items checked out': (browser: NightwatchBrowser) => {
        browser.click('xpath', '//a[contains(text(), "View Items Out")]')
               .assert.textContains('body', 'Throne of the Crescent Moon');
    },

    'Previously checked out items are cleared on logout': (browser: NightwatchBrowser) => {
        browser.click('label[for="receipt-none"]') // We don't want to deal with the browser print dialog in this test
               .click('xpath', '//button[contains(text(), "Logout")]')
               .setValue('#patron-username', '99999342948') // Patron Omar Bernard from the concerto data set
               .submitForm('#patron-username')
               .assert.valueEquals('#item-barcode', '');
    },

    'Cleanup': (broser: NightwatchBrowser) => {
        browser.navigateTo('/eg2/en-US/staff/circ/checkin')
               .setValue('#barcode-input', 'FIC400001583')
               .click('xpath', '//button[contains(text(), "Submit")]');
    }


};
