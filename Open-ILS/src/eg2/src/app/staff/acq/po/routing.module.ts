import {NgModule} from '@angular/core';
import {RouterModule, Routes} from '@angular/router';
import {PoComponent} from './po.component';
import {PrintComponent} from './print.component';
import {PoSummaryComponent} from './summary.component';
import {LineitemListComponent} from '../lineitem/lineitem-list.component';
import {LineitemDetailComponent} from '../lineitem/detail.component';
import {LineitemCopiesComponent} from '../lineitem/copies.component';
import {BriefRecordComponent} from '../lineitem/brief-record.component';
import {LineitemHistoryComponent} from '../lineitem/history.component';
import {LineitemWorksheetComponent} from '../lineitem/worksheet.component';
import {PoHistoryComponent} from './history.component';
import {PoEdiMessagesComponent} from './edi.component';
import {PoCreateComponent} from './create.component';

const routes: Routes = [{
  path: 'create',
  component: PoCreateComponent
}, {
  path: ':poId',
  component: PoComponent,
  children : [{
    path: '',
    component: LineitemListComponent
  }, {
    path: 'history',
    component: PoHistoryComponent
  }, {
    path: 'edi',
    component: PoEdiMessagesComponent
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
  }, {
    path: 'printer',
    component: PrintComponent
  }, {
    path: 'printer/print',
    component: PrintComponent
  }, {
    path: 'printer/print/close',
    component: PrintComponent
  }]
}];

@NgModule({
  imports: [RouterModule.forChild(routes)],
  exports: [RouterModule],
  providers: []
})

export class PoRoutingModule {}
