import {NgModule} from '@angular/core';
import {RouterModule, Routes} from '@angular/router';
import {VandelayComponent} from './vandelay.component';
import {ImportComponent} from './import.component';
import {ExportComponent} from './export.component';
import {QueueListComponent} from './queue-list.component';
import {QueueComponent} from './queue.component';
import {BackgroundImportComponent} from './background-import.component';
import {QueuedRecordComponent} from './queued-record.component';
import {DisplayAttrsComponent} from './display-attrs.component';
import {MergeProfilesComponent} from './merge-profiles.component';
import {HoldingsProfilesComponent} from './holdings-profiles.component';
import {QueueItemsComponent} from './queue-items.component';
import {MatchSetListComponent} from './match-set-list.component';
import {MatchSetComponent} from './match-set.component';
import {RecentImportsComponent} from './recent-imports.component';
import {UploadComponent} from '../../acq/picklist/upload.component';
import {PicklistUploadService} from '../../acq/picklist/upload.service';

const routes: Routes = [{
    path: '',
    component: VandelayComponent,
    children: [{
        path: '',
        pathMatch: 'full',
        redirectTo: 'import'
    }, {
        path: 'import',
        component: ImportComponent
    }, {
        path: 'acqimport',
        component: UploadComponent
    }, {
        path: 'export',
        component: ExportComponent
    }, {
        path: 'export/basket',
        component: ExportComponent
    }, {
        path: 'background-import',
        component: BackgroundImportComponent
    }, {
        path: 'queue',
        component: QueueListComponent
    }, {
        path: 'queue/:qtype/:id',
        component: QueueComponent
    }, {
        path: 'queue/:qtype/:id/record/:recordId',
        component: QueuedRecordComponent
    }, {
        path: 'queue/:qtype/:id/record/:recordId/:recordTab',
        component: QueuedRecordComponent
    }, {
        path: 'queue/:qtype/:id/items',
        component: QueueItemsComponent
    }, {
        path: 'display_attrs',
        component: DisplayAttrsComponent
    }, {
        path: 'display_attrs/:atype',
        component: DisplayAttrsComponent
    }, {
        path: 'merge_profiles',
        component: MergeProfilesComponent
    }, {
        path: 'holdings_profiles',
        component: HoldingsProfilesComponent
    }, {
        path: 'match_sets',
        component: MatchSetListComponent
    }, {
        path: 'match_sets/:id/:matchSetTab',
        component: MatchSetComponent
    }, {
        path: 'active_imports',
        component: RecentImportsComponent
    }]
}];

@NgModule({
    imports: [RouterModule.forChild(routes)],
    exports: [RouterModule],
    providers: [PicklistUploadService]
})

export class VandelayRoutingModule {}
