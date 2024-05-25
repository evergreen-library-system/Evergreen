import {NightwatchBrowser} from 'nightwatch';
import {randomString} from '../../../../utils';

const courseData = [
    {name: randomString().slice(0, 5), number: randomString().slice(0, 5)},
    {name: randomString().slice(0, 5), number: randomString().slice(0, 5)}
]

module.exports = {
    before: (browser: NightwatchBrowser) => {
        // log in as circ admin
        browser.page.login().loginToWebClient(browser, 'br3kwright', 'kayw1234');
        browser.navigateTo('eg2/en-US/staff/admin/local/asset/course_list')
            
        // Change the grid to show more rows
        browser.click('xpath', '//*[contains(text(), "Rows 10")]')
        .click('xpath', '//button/*[contains(text(), "50")]');
    },

    'Can create courses': (browser: NightwatchBrowser) => {
        courseData.forEach((course) => {
            browser.click('xpath', '//button[contains(text(), "Create Course")]')
            .setValue('xpath', '//input[contains(@id, "course_number")]', course.number)
            .setValue('xpath', '//input[contains(@id, "name")]', course.name)
            .click('xpath', '//button[contains(text(), "Save")]')
            .assert.textContains('eg-grid', course.name, 'Grid has refreshed and is now showing the first part of the course name');
        })
    },

    'Can duplicate courses': (browser: NightwatchBrowser) => {
        browser.click('thead.eg-grid-header input')
        .rightClick('eg-grid-body-cell a')
        .click('xpath', '//ngb-popover-window//button/span[contains(text(), "Duplicate Selected")]')
        .assert.textContains('eg-grid', courseData[0].name + ' (Copy)')
        .assert.textContains('eg-grid', courseData[1].name + ' (Copy)');
    },

    'Can delete courses': (browser: NightwatchBrowser) => {
        browser.click('thead.eg-grid-header input')
        .rightClick('eg-grid-body-cell a')
        .click('xpath', '//ngb-popover-window//button/span[contains(text(), "Delete Selected")]')
        .assert.textContains('body', 'Deletion of Course was successful');
    }
};
