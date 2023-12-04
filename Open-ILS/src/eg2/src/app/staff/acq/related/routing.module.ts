import {NgModule} from '@angular/core';
import {RouterModule, Routes} from '@angular/router';
import {LineitemListComponent} from '../lineitem/lineitem-list.component';
import {LineitemDetailComponent} from '../lineitem/detail.component';
import {LineitemCopiesComponent} from '../lineitem/copies.component';
import {BriefRecordComponent} from '../lineitem/brief-record.component';
import {LineitemHistoryComponent} from '../lineitem/history.component';
import {LineitemWorksheetComponent} from '../lineitem/worksheet.component';
import {RelatedComponent} from './related.component';

const routes: Routes = [{
    path: ':recordId',
    component: RelatedComponent,
    children : [{
        path: '',
        component: LineitemListComponent
    }, {
        path: 'brief-record',
        component: BriefRecordComponent
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
    providers: []
})

export class RelatedRoutingModule {}
