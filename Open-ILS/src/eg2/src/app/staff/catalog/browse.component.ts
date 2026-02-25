import { Component, OnInit, ViewChild, inject } from '@angular/core';
import {StaffCatalogService} from './catalog.service';
import {SearchFormComponent} from './search-form.component';
import { StaffCommonModule } from '../common.module';
import { BrowseResultsComponent } from './browse/results.component';

@Component({
    templateUrl: 'browse.component.html',
    imports: [
        BrowseResultsComponent,
        SearchFormComponent,
        StaffCommonModule
    ]
})
export class BrowseComponent implements OnInit {
    private staffCat = inject(StaffCatalogService);


    @ViewChild('searchForm', { static: true }) searchForm: SearchFormComponent;

    ngOnInit() {
        // A SearchContext provides all the data needed for browse.
        this.staffCat.createContext();
        this.searchForm.searchTab = 'browse';
    }
}

