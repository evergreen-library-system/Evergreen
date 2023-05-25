import {NgModule} from '@angular/core';
import {RouterModule, Routes} from '@angular/router';
import {PicklistComponent} from './picklist.component';
import {PicklistSummaryComponent} from './summary.component';
import {LineitemListComponent} from '../lineitem/lineitem-list.component';
import {LineitemDetailComponent} from '../lineitem/detail.component';
import {LineitemCopiesComponent} from '../lineitem/copies.component';
import {LineitemWorksheetComponent} from '../lineitem/worksheet.component';
import {LineitemFromBibIdsComponent} from '../lineitem/from-bib-ids.component';
import {BriefRecordComponent} from '../lineitem/brief-record.component';
import {LineitemHistoryComponent} from '../lineitem/history.component';
import {UploadComponent} from './upload.component';
import {VandelayService} from '@eg/staff/cat/vandelay/vandelay.service';
import {PicklistUploadService} from './upload.service';
import {Z3950SearchComponent} from '@eg/staff/share/z3950-search/z3950-search.component';

const routes: Routes = [{
    path: 'brief-record',
    component: BriefRecordComponent
}, {
    path: 'from-bib-ids',
    component: LineitemFromBibIdsComponent
}, {
    path: 'upload',
    component: UploadComponent
}, {
    path: 'z3950-search',
    component: Z3950SearchComponent,
    data: { searchMode: 'acq' }
}, {
    path: ':picklistId',
    component: PicklistComponent,
    children : [{
        path: '',
        component: LineitemListComponent
    }, {
        path: 'brief-record',
        component: BriefRecordComponent
    }, {
        path: 'from-bib-ids',
        component: LineitemFromBibIdsComponent
    }, {
        path: 'lineitem/:lineitemId/detail',
        component: LineitemDetailComponent
    }, {
        path: 'lineitem/:lineitemId/history',
        component: LineitemHistoryComponent
    }, {
        path: 'lineitem/:lineitemId/items',
        component: LineitemCopiesComponent
    }, {
        path: 'lineitem/:lineitemId/worksheet',
        component: LineitemWorksheetComponent
    }]
}];

@NgModule({
    imports: [RouterModule.forChild(routes)],
    exports: [RouterModule],
    providers: [VandelayService, PicklistUploadService]
})

export class PicklistRoutingModule {}
