import {Component, OnInit, Input} from '@angular/core';
import {OrgService} from '@eg/core/org.service';
import {CourseService} from '@eg/staff/share/course.service';
import {BibRecordService, BibRecordSummary
} from '@eg/share/catalog/bib-record.service';
import {ServerStoreService} from '@eg/core/server-store.service';
import {CatalogService} from '@eg/share/catalog/catalog.service';

@Component({
    selector: 'eg-bib-summary',
    templateUrl: 'bib-summary.component.html',
    styleUrls: ['bib-summary.component.css']
})
export class BibSummaryComponent implements OnInit {

    initDone = false;
    hasCourse = false;
    courses: any;

    // True / false if the display is vertically expanded
    private _exp: boolean;
    set expand(e: boolean) {
        this._exp = e;
        if (this.initDone) {
            this.saveExpandState();
        }
    }
    get expand(): boolean { return this._exp; }

    // If provided, the record will be fetched by the component.
    @Input() recordId: number;

    // Otherwise, we'll use the provided bib summary object.
    summary: BibRecordSummary;
    @Input() set bibSummary(s: any) {
        this.summary = s;
        if (this.initDone && this.summary) {
            this.summary.getBibCallNumber();
            this.loadCourseInformation(this.summary.record.id());
        }
    }

    constructor(
        private bib: BibRecordService,
        private org: OrgService,
        private store: ServerStoreService,
        private cat: CatalogService,
        private course: CourseService
    ) {}

    ngOnInit() {

        this.store.getItem('eg.cat.record.summary.collapse')
            .then(value => this.expand = !value)
            .then(_ => this.cat.fetchCcvms())
            .then(_ => {
                if (this.summary) {
                    return this.loadCourseInformation(this.summary.record.id())
                        .then(__ => this.summary.getBibCallNumber());
                } else {
                    if (this.recordId) {
                        return this.loadSummary();
                    }
                }
            }).then(_ => this.initDone = true);
    }

    saveExpandState() {
        this.store.setItem('eg.cat.record.summary.collapse', !this.expand);
    }

    loadSummary(): Promise<any> {
        return this.loadCourseInformation(this.recordId)
            .then(_ => {
                return this.bib.getBibSummary(this.recordId).toPromise()
                    .then(summary => {
                        this.summary = summary;
                        return summary.getBibCallNumber();
                    });
            });
    }

    loadCourseInformation(recordId): Promise<any> {
        return this.org.settings('circ.course_materials_opt_in')
            .then(setting => {
                if (setting['circ.course_materials_opt_in']) {
                    this.course.fetchCoursesForRecord(recordId).then(courseList => {
                        if (courseList) {
                            this.courses = courseList;
                            this.hasCourse = true;
                        }
                    });
                }
            });
    }

    orgName(orgId: number): string {
        if (orgId) {
            return this.org.get(orgId).shortname();
        }
    }

    iconFormatLabel(code: string): string {
        return this.cat.iconFormatLabel(code);
    }
}


