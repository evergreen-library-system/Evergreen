import {Component, OnInit, OnDestroy, Input} from '@angular/core';
import {Subscription} from 'rxjs';
import {Router} from '@angular/router';
import {OrgService} from '@eg/core/org.service';
import {IdlObject} from '@eg/core/idl.service';
import {CatalogService} from '@eg/share/catalog/catalog.service';
import {BibRecordSummary, HoldingsSummary} from '@eg/share/catalog/bib-record.service';
import {CatalogSearchContext} from '@eg/share/catalog/search-context';
import {CatalogUrlService} from '@eg/share/catalog/catalog-url.service';
import {StaffCatalogService} from '../catalog.service';
import {BasketService} from '@eg/share/catalog/basket.service';
import {CourseService} from '@eg/staff/share/course.service';

@Component({
  selector: 'eg-catalog-result-record',
  templateUrl: 'record.component.html',
  styleUrls: ['record.component.css']
})
export class ResultRecordComponent implements OnInit, OnDestroy {

    @Input() index: number;  // 0-index display row
    @Input() summary: BibRecordSummary;

    // Optional call number (acn) object to highlight
    // Assumed prefix/suffix are fleshed
    // Used by call number browse.
    @Input() callNumber: IdlObject;

    searchContext: CatalogSearchContext;
    isRecordSelected: boolean;
    basketSub: Subscription;
    hasCourse = false;
    courses: any[] = [];

    constructor(
        private router: Router,
        private org: OrgService,
        private cat: CatalogService,
        private catUrl: CatalogUrlService,
        private staffCat: StaffCatalogService,
        private basket: BasketService,
        private course: CourseService
    ) {}

    ngOnInit() {
        this.searchContext = this.staffCat.searchContext;
        this.loadCourseInformation(this.summary.id);
        this.isRecordSelected = this.basket.hasRecordId(this.summary.id);

        // Watch for basket changes caused by other components
        this.basketSub = this.basket.onChange.subscribe(() => {
            this.isRecordSelected = this.basket.hasRecordId(this.summary.id);
        });
    }

    ngOnDestroy() {
        this.basketSub.unsubscribe();
    }

    loadCourseInformation(recordId) {
        this.course.isOptedIn().then(res => {
            if (res) {
                this.course.fetchCoursesForRecord(recordId).then(course_list => {
                    if (course_list) {
                        Object.keys(course_list).forEach(key => {
                            this.courses.push(course_list[key]);
                        });
                        this.hasCourse = true;
                    }
                });
            }
        });
    }

    orgName(orgId: number): string {
        return this.org.get(orgId).shortname();
    }

    iconFormatLabel(code: string): string {
        return this.cat.iconFormatLabel(code);
    }

    placeHold(): void {
        let holdType = 'T';
        let holdTarget = this.summary.id;

        const ts = this.searchContext.termSearch;
        if (ts.isMetarecordSearch()) {
            holdType = 'M';
            holdTarget = this.summary.metabibId;
        }

        this.router.navigate([`/staff/catalog/hold/${holdType}`],
            {queryParams: {target: holdTarget}});
    }

    addToList(): void {
        alert('Adding to list for bib ' + this.summary.id);
    }

    // Params to genreate a new author search based on a reset
    // clone of the current page params.
    getAuthorSearchParams(summary: BibRecordSummary): any {
        return this.staffCat.getAuthorSearchParams(summary);
    }

    // Returns the URL parameters for the current page plus the
    // "fromMetarecord" param used for linking title links to
    // MR constituent result records list.
    appendFromMrParam(summary: BibRecordSummary): any {
        const tmpContext = this.staffCat.cloneContext(this.searchContext);
        tmpContext.termSearch.fromMetarecord = summary.metabibId;
        return this.catUrl.toUrlParams(tmpContext);
    }

    // Returns true if the selected record summary is a metarecord summary
    // and it links to more than one constituent bib record.
    hasMrConstituentRecords(summary: BibRecordSummary): boolean {
        return (
            summary.metabibId && summary.metabibRecords.length > 1
        );
    }

    currentParams(): any {
        return this.catUrl.toUrlParams(this.searchContext);
    }

    toggleBasketEntry() {
        if (this.isRecordSelected) {
            return this.basket.addRecordIds([this.summary.id]);
        } else {
            return this.basket.removeRecordIds([this.summary.id]);
        }
    }

    getHoldingsSummaries(): HoldingsSummary[] {
        if (!this.summary.prefOuHoldingsSummary) {
            return this.summary.holdingsSummary;
        }

        let match = false;
        this.summary.holdingsSummary.some(sum => {
            if (Number(sum.org_unit) === Number(this.staffCat.prefOrg.id())) {
                return match = true;
            }
        });

        if (match) {
            // Holdings summary for the pref ou is included in the
            // record-level holdings summaries.
            return this.summary.holdingsSummary;
        }

        return this.summary.holdingsSummary
            .concat(this.summary.prefOuHoldingsSummary);
    }
}


