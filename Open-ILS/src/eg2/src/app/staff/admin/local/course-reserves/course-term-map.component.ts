import {Component} from '@angular/core';
import {ActivatedRoute} from '@angular/router';

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
                <a class="btn btn-info ml-3" routerLink="/staff/admin/local/asset/course_list" i18n>
                    <i class="material-icons align-middle" aria-hidden="true">keyboard_return</i>
                    <span class="align-middle">Return to Course List</span>
                </a>
            </div>
        </div>
        <eg-course-term-map-grid [courseId]="courseId"></eg-course-term-map-grid>
    `
})

export class CourseTermMapComponent {
    public courseId: number;

    constructor(private route: ActivatedRoute) {
        const filters = this.route.snapshot.queryParamMap.get('gridFilters');
        this.courseId = JSON.parse(filters)['course'] || 1;
    }


}
