import {Component, OnInit, Input} from '@angular/core';
import {CatalogService} from '@eg/share/catalog/catalog.service';
import {CatalogSearchContext} from '@eg/share/catalog/search-context';
import {StaffCatalogService} from '../catalog.service';

@Component({
  selector: 'eg-catalog-result-pagination',
  styleUrls: ['pagination.component.css'],
  templateUrl: 'pagination.component.html'
})
export class ResultPaginationComponent implements OnInit {

    searchContext: CatalogSearchContext;

    // Maximum number of jump-to-page buttons displayed.
    @Input() numPages: number;

    constructor(
        private cat: CatalogService,
        private staffCat: StaffCatalogService
    ) {
        this.numPages = 10;
    }

    ngOnInit() {
        this.searchContext = this.staffCat.searchContext;
    }

    currentPageList(): number[] {
        const pgr = this.searchContext.pager;
        return pgr.pageRange(pgr.currentPage(), this.numPages);
    }

    nextPage(): void {
        this.searchContext.pager.increment();
        this.staffCat.search();
    }

    prevPage(): void {
        this.searchContext.pager.decrement();
        this.staffCat.search();
    }

    setPage(page: number): void {
        if (this.searchContext.pager.currentPage() === page) { return; }
        this.searchContext.pager.setPage(page);
        this.staffCat.search();
    }
}


