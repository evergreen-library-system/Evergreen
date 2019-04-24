import {Component, OnInit, OnDestroy, Input} from '@angular/core';
import {Subscription} from 'rxjs';
import {Router} from '@angular/router';
import {OrgService} from '@eg/core/org.service';
import {NetService} from '@eg/core/net.service';
import {CatalogService} from '@eg/share/catalog/catalog.service';
import {BibRecordService, BibRecordSummary} from '@eg/share/catalog/bib-record.service';
import {CatalogSearchContext} from '@eg/share/catalog/search-context';
import {CatalogUrlService} from '@eg/share/catalog/catalog-url.service';
import {StaffCatalogService} from '../catalog.service';
import {BasketService} from '@eg/share/catalog/basket.service';

@Component({
  selector: 'eg-catalog-result-record',
  templateUrl: 'record.component.html',
  styleUrls: ['record.component.css']
})
export class ResultRecordComponent implements OnInit, OnDestroy {

    @Input() index: number;  // 0-index display row
    @Input() summary: BibRecordSummary;
    searchContext: CatalogSearchContext;
    isRecordSelected: boolean;
    basketSub: Subscription;

    constructor(
        private router: Router,
        private org: OrgService,
        private net: NetService,
        private bib: BibRecordService,
        private cat: CatalogService,
        private catUrl: CatalogUrlService,
        private staffCat: StaffCatalogService,
        private basket: BasketService
    ) {}

    ngOnInit() {
        this.searchContext = this.staffCat.searchContext;
        this.summary.getHoldCount();
        this.isRecordSelected = this.basket.hasRecordId(this.summary.id);

        // Watch for basket changes caused by other components
        this.basketSub = this.basket.onChange.subscribe(() => {
            this.isRecordSelected = this.basket.hasRecordId(this.summary.id);
        });
    }

    ngOnDestroy() {
        this.basketSub.unsubscribe();
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

    searchAuthor(summary: any) {
        this.searchContext.reset();
        this.searchContext.termSearch.fieldClass = ['author'];
        this.searchContext.termSearch.query = [summary.display.author];
        this.staffCat.search();
    }

    /**
     * Propagate the search params along when navigating to each record.
     */
    navigateToRecord(summary: BibRecordSummary) {
        const params = this.catUrl.toUrlParams(this.searchContext);

        // Jump to metarecord constituent records page when a
        // MR has more than 1 constituents.
        if (summary.metabibId && summary.metabibRecords.length > 1) {
            this.searchContext.termSearch.fromMetarecord = summary.metabibId;
            this.staffCat.search();
            return;
        }

        this.router.navigate(
            ['/staff/catalog/record/' + summary.id], {queryParams: params});
    }

    toggleBasketEntry() {
        if (this.isRecordSelected) {
            return this.basket.addRecordIds([this.summary.id]);
        } else {
            return this.basket.removeRecordIds([this.summary.id]);
        }
    }
}


