import { Component, OnInit, ViewChild, inject } from '@angular/core';
import {StaffCatalogService} from './catalog.service';
import {SearchFormComponent} from './search-form.component';
import { StaffCommonModule } from '../common.module';
import { CnBrowseResultsComponent } from './cnbrowse/results.component';

@Component({
    templateUrl: 'cnbrowse.component.html',
    imports: [
        SearchFormComponent,
        CnBrowseResultsComponent,
        StaffCommonModule
    ]
})
export class CnBrowseComponent implements OnInit {
    private staffCat = inject(StaffCatalogService);


    @ViewChild('searchForm', { static: true }) searchForm: SearchFormComponent;

    ngOnInit() {
        // A SearchContext provides all the data needed for browse.
        this.staffCat.createContext();
        this.searchForm.searchTab = 'cnbrowse';
    }
}

