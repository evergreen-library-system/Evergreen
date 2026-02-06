import {Component, OnInit, ViewChild} from '@angular/core';
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

    @ViewChild('searchForm', { static: true }) searchForm: SearchFormComponent;

    constructor(
        private staffCat: StaffCatalogService,
    ) {}

    ngOnInit() {
        // A SearchContext provides all the data needed for browse.
        this.staffCat.createContext();
        this.searchForm.searchTab = 'cnbrowse';
    }
}

