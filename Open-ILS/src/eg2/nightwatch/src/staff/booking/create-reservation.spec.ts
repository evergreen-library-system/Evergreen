import {NightwatchBrowser} from 'nightwatch';


module.exports = {
    before: (browser: NightwatchBrowser) => {
        browser.page.login().loginToWebClient(browser, 'br1mneal', 'demo123'); // circulation admin
    },

    after: (browser: NightwatchBrowser) => {
        browser.end();
    },
    'Can create a new reservation for a specific resource': (browser: NightwatchBrowser) => {
        browser.page.navbar().click('@bookingMenu')
               .click('@bookingMenuCreateReservations')
               .click('xpath', '//a[contains(text(), "Choose resource by barcode")]')
               .setValue('#ideal-resource-barcode', 'ROOM1231')
               // Select a day
               .click('xpath', '//button[contains(./span/text(), "Next day")]')
               // Select a time
               .click('.eg-grid-body .eg-grid-checkbox-cell input')
               .click('xpath', '//button[contains(text(), "Create Reservation")]')
               .setValue('#create-patron-barcode', '99999372586')
               .click('xpath', '//button[contains(text(), "Confirm and show patron reservations")]')
               .assert.textContains('eg-grid', 'ROO', 'Grid has refreshed and is showing the first part of the resource barcode');
    }

};
