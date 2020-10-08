import {NgModule} from '@angular/core';
import {RouterModule, Routes} from '@angular/router';
import {PicklistComponent} from './picklist.component';
import {PicklistSummaryComponent} from './summary.component';
import {LineitemListComponent} from '../lineitem/lineitem-list.component';
import {LineitemDetailComponent} from '../lineitem/detail.component';
import {LineitemCopiesComponent} from '../lineitem/copies.component';
import {LineitemWorksheetComponent} from '../lineitem/worksheet.component';
import {BriefRecordComponent} from '../lineitem/brief-record.component';
import {LineitemHistoryComponent} from '../lineitem/history.component';

const routes: Routes = [{
  path: ':picklistId',
  component: PicklistComponent,
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

export class PicklistRoutingModule {}
