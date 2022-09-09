import {NightwatchBrowser, PageObjectModel} from 'nightwatch';
import {navigateToEgUrl} from '../../src/utils';

function fillInLoginForm(browser: NightwatchBrowser, username: string, password: string): void {
    browser.setValue('#username', username)
    .setValue('#password', password)
    .click('button[type=submit]');
}

const loginCommands = {
    loginToWebClient: function(browser: NightwatchBrowser, username: string, password: string): void {
        navigateToEgUrl('eg2/staff', browser);
        fillInLoginForm(browser, username, password);
        browser.page.workstationAdmin().registerWorkstation();
        browser.waitForElementVisible('#username');
        fillInLoginForm(browser, username, password); // Submit the form again, now that we have a workstation
        browser.waitForElementVisible('#splash-nav');
    }
};

const loginPage: PageObjectModel = {
    commands: [loginCommands]
};

export default loginPage;