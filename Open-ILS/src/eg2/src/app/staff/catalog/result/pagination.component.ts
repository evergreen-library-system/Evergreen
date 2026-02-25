import { Component, OnInit, Input, inject } from '@angular/core';
import {CatalogSearchContext} from '@eg/share/catalog/search-context';
import {StaffCatalogService} from '../catalog.service';
import { StaffCommonModule } from '@eg/staff/common.module';

@Component({
    selector: 'eg-catalog-result-pagination',
    styleUrls: ['pagination.component.css'],
    templateUrl: 'pagination.component.html',
    imports: [StaffCommonModule]
})
export class ResultPaginationComponent implements OnInit {
    private staffCat = inject(StaffCatalogService);


    searchContext: CatalogSearchContext;

    // Maximum number of jump-to-page buttons displayed.
    @Input() numPages: number;

    constructor() {
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


