import {Component} from '@angular/core';

/**
 * Very basic page for editing course/term map
 */

@Component({
    template: `
        <eg-title i18n-prefix prefix="Course Materials Administration">
        </eg-title>
        <eg-staff-banner bannerText="Course Term Configuration" i18n-bannerText>
        </eg-staff-banner>
        <div class="row">
            <div class="col text-right">
                <a class="btn btn-warning ml-3" routerLink="/staff/admin/local/asset/course_list" i18n>
                    <i class="material-icons align-middle">keyboard_return</i>
                    <span class="align-middle">Return to Course List</span>
                </a>
            </div>
        </div>
        <eg-admin-page persistKeyPfx="local" idlClass="acmtcm"
            [disableOrgFilter]="true"></eg-admin-page>
    `
})

export class CourseTermMapComponent {

}
