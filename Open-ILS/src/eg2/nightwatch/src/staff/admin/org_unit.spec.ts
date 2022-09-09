import {NightwatchBrowser} from 'nightwatch';
import {navigateToEgUrl, fmEditorFieldSelector} from '../../utils';

module.exports = {
    before: (browser: NightwatchBrowser) => {
        // System administrator housed at BR3
        browser.page.login().loginToWebClient(browser, 'br3cmartin', 'carlm1234');
    },

    after: (browser: NightwatchBrowser) => {
        browser.end();
    },

    'Can edit an org unit address': (browser: NightwatchBrowser) => {
        navigateToEgUrl('/eg2/en-US/staff/admin/server/actor/org_unit', browser);
        const orgUnitAdmin = browser.page.orgUnitAdmin();
        // Sometimes this part of the org tree is already expanded, sometimes not...
        orgUnitAdmin.api.element('@system2expand', (result) => {
            if (result.status != -1) {
                orgUnitAdmin.click('@system2expand');
            }
        });
        orgUnitAdmin.click('@br3')
                    .click('#addresses')
                    .click('#ill_address')
                    .setValue(fmEditorFieldSelector('Street1'), 'Apartment 221B')
                    .click('@saveButton')
                    .assert.visible('#eg-toast-container')
                    .assert.containsText('#eg-toast-container', 'Update Succeeded');
    }
};
