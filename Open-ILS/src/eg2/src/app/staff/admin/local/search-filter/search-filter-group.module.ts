import {NgModule} from '@angular/core';
import {AdminCommonModule} from '@eg/staff/admin/common.module';
import {SearchFilterGroupComponent} from './search-filter-group.component';
import {SearchFilterGroupEntriesComponent} from './search-filter-group-entries.component';
import {SearchFilterGroupRoutingModule} from './search-filter-group-routing.module';
import {QueryDialogComponent} from './query-dialog.component';

@NgModule({
    declarations: [
        SearchFilterGroupComponent,
        SearchFilterGroupEntriesComponent,
        QueryDialogComponent
    ],
    imports: [
        AdminCommonModule,
        SearchFilterGroupRoutingModule,
    ],
    exports: [
    ],
    providers: [
    ]
})

export class SearchFilterGroupModule {}
