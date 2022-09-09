import {EnhancedPageObject, PageObjectModel} from 'nightwatch';
import {randomString} from '../../../src/utils';

const workstationAdminCommands = {
    registerWorkstation: function(this: EnhancedPageObject): void {
        const workstationName = randomString();

        this.setValue('@workstationName', workstationName)
            .click('@registerButton')
            .waitForElementVisible('option')
            .click('button.btn-success');
    }
};

const workstationAdmin: PageObjectModel = {
    commands: [workstationAdminCommands],
    elements: {
        registerButton: {
            selector: '//button[not(@disabled)]/span[text() = "Register"]',
            locateStrategy: 'xpath'
        },
        workstationName: {
            selector: 'input[title="Workstation Name"]'
        }
    },
    url: 'https://localhost/eg2/en-US/staff/admin/workstation/workstations/manage'
};

export default workstationAdmin;