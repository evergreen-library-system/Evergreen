import {Component, OnInit, Input} from '@angular/core';
import {Router} from '@angular/router';
import {OrgService} from '@eg/core/org.service';
import {NetService} from '@eg/core/net.service';
import {CatalogService} from '@eg/share/catalog/catalog.service';
import {BibRecordService, BibRecordSummary} from '@eg/share/catalog/bib-record.service';
import {CatalogSearchContext} from '@eg/share/catalog/search-context';
import {CatalogUrlService} from '@eg/share/catalog/catalog-url.service';
import {StaffCatalogService} from '../catalog.service';

@Component({
  selector: 'eg-catalog-result-record',
  templateUrl: 'record.component.html'
})
export class ResultRecordComponent implements OnInit {

    @Input() index: number;  // 0-index display row
    @Input() summary: BibRecordSummary;
    searchContext: CatalogSearchContext;

    constructor(
        private router: Router,
        private org: OrgService,
        private net: NetService,
        private bib: BibRecordService,
        private cat: CatalogService,
        private catUrl: CatalogUrlService,
        private staffCat: StaffCatalogService
    ) {}

    ngOnInit() {
        this.searchContext = this.staffCat.searchContext;
        this.summary.getHoldCount();
    }

    orgName(orgId: number): string {
        return this.org.get(orgId).shortname();
    }

    iconFormatLabel(code: string): string {
        if (this.cat.ccvmMap) {
            const ccvm = this.cat.ccvmMap.icon_format.filter(
                format => format.code() === code)[0];
            if (ccvm) {
                return ccvm.search_label();
            }
        }
    }

    placeHold(): void {
        alert('Placing hold on bib ' + this.summary.id);
    }

    addToList(): void {
        alert('Adding to list for bib ' + this.summary.id);
    }

    searchAuthor(summary: any) {
        this.searchContext.reset();
        this.searchContext.fieldClass = ['author'];
        this.searchContext.query = [summary.display.author];
        this.staffCat.search();
    }

    /**
     * Propagate the search params along when navigating to each record.
     */
    navigatToRecord(id: number) {
        const params = this.catUrl.toUrlParams(this.searchContext);

        this.router.navigate(
          ['/staff/catalog/record/' + id], {queryParams: params});
    }

}


