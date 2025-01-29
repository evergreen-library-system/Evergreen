import {Component, OnInit, OnDestroy, Input, ViewChild} from '@angular/core';
import {Subject, BehaviorSubject, Subscription, lastValueFrom, EMPTY} from 'rxjs';
import {catchError, takeUntil} from 'rxjs/operators';
import {Router} from '@angular/router';
import {OrgService} from '@eg/core/org.service';
import {IdlObject} from '@eg/core/idl.service';
import {CatalogService} from '@eg/share/catalog/catalog.service';
import {BibRecordSummary, HoldingsSummary} from '@eg/share/catalog/bib-record.service';
import {CatalogSearchContext} from '@eg/share/catalog/search-context';
import {CatalogUrlService} from '@eg/share/catalog/catalog-url.service';
import {StaffCatalogService} from '../catalog.service';
import {BasketService} from '@eg/share/catalog/basket.service';
import {BucketService} from '@eg/staff/share/buckets/bucket.service';
import {CourseService} from '@eg/staff/share/course.service';
import {AuthService} from '@eg/core/auth.service';
import {ToastService} from '@eg/share/toast/toast.service';
import {BucketDialogComponent} from '@eg/staff/share/buckets/bucket-dialog.component';
import {ResultFacetsComponent} from './facets.component';

@Component({
    selector: 'eg-catalog-result-record',
    templateUrl: 'record.component.html',
    styleUrls: ['record.component.css']
})
export class ResultRecordComponent implements OnInit, OnDestroy {

    @ViewChild('addRecordToBucketDialog', { static: true })
        addToBucketDialog: BucketDialogComponent;

    private destroy$ = new Subject<void>();

    favoriteBuckets$ = new BehaviorSubject<any[]>([]);
    recentBuckets$ = new BehaviorSubject<any[]>([]);

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
    favoriteBucketIds: number[] = [];
    recentBucketIds: number[] = [];
    recordIds: number[] = [];

    constructor(
        private router: Router,
        private org: OrgService,
        private cat: CatalogService,
        private catUrl: CatalogUrlService,
        private staffCat: StaffCatalogService,
        private basket: BasketService,
        private course: CourseService,
        private bucketService: BucketService,
        private auth: AuthService,
        private toast: ToastService,
    ) {}

    async ngOnInit() {
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
        this.destroy$.next();
        this.destroy$.complete();
    }

    async loadBuckets() {
        await this.bucketService.loadFavoriteRecordBucketFlags(this.auth.user().id());
        this.favoriteBucketIds = this.bucketService.getFavoriteRecordBucketIds();
        this.recentBucketIds = this.bucketService.recentRecordBucketIds();
        const favoriteBuckets = await this.bucketService.retrieveRecordBuckets(this.favoriteBucketIds);
        this.favoriteBuckets$.next(favoriteBuckets);
        const recentBuckets = await this.bucketService.retrieveRecordBuckets(this.recentBucketIds);
        this.recentBuckets$.next(recentBuckets);
    }

    async updateBucketList($event) {
        if ($event) {
            // we're opening, so fetch the buckets
            await this.loadBuckets();
        }
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
        return this.org.get(orgId)?.shortname();
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

    async toggleRecordInBucket(bibId: number, bucketId: number) {
        const bibIds = new Array(bibId);
        const inBucket = await this.bucketService.checkForBibInRecordBuckets(bibId, new Array(bucketId));
        if (inBucket) {
            await this.bucketService.removeBibsFromRecordBucket(bucketId, bibIds);
        } else {
            await this.bucketService.addBibsToRecordBucket(bucketId, bibIds);
        }
    }

    chooseBucket = async (bibId: number) => {
        console.debug('chooseBucket, invoked');
        try {
            this.recordIds = [bibId];
            const dialogObservable = this.addToBucketDialog.open({size: 'lg'}).pipe(
                catchError((error: unknown) => {
                    console.debug('Error in dialog observable; this can happen if we close() with no arguments:', error);
                    return EMPTY;
                }),
                takeUntil(this.destroy$),
            );

            const results = await lastValueFrom(dialogObservable, { defaultValue: null });
            console.debug('chooseBucket results:', results);

            this.bucketService.requestBibBucketsRefresh();

        } catch (error) {
            console.error('chooseBucket, error in dialog:', error);
        }
    };

    async addRecordToBucket(bibId: number, bucketId: number): Promise<any> {
        console.debug('addRecordToBucket, invoked');
        this.bucketService.logRecordBucket(bucketId);
        let msg = '';
        const result = await this.bucketService.addBibsToRecordBucket(bucketId, [bibId]);
        // eslint-disable-next-line eqeqeq
        if (result.textcode == 'DATABASE_UPDATE_FAILED') {
            msg = $localize`Error adding to bucket`;
            console.log(msg, result.debug);
            this.toast.warning(msg);
        } else {
            msg = $localize`Added record ${bibId} to bucket ${bucketId}`;
            console.log(msg);
            this.toast.success(msg);
            this.bucketService.requestBibBucketsRefresh();
        }

    }

    async recordInBucket(bibId: number, bucketId: number): Promise<any> {
        return await this.bucketService.checkForBibInRecordBuckets(bibId, new Array(bucketId));
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


