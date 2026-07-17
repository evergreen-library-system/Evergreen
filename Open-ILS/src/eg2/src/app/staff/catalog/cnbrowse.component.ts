import { Component, OnInit, ViewChild, inject } from '@angular/core';
import {StaffCatalogService} from './catalog.service';
import {SearchFormComponent} from './search-form.component';
import { StaffCommonModule } from '../common.module';
import { CnBrowseResultsComponent } from './cnbrowse/results.component';

@Component({
    templateUrl: 'cnbrowse.component.html',
    // we don't use this selector; just declaring one to avoid an NG0912
    // warning about an ID collision with BrowseComponent
    selector: 'eg-cnbrowse',
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

