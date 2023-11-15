import {NgModule, Injectable} from '@angular/core';
import {RouterModule, Routes, CanDeactivate} from '@angular/router';
import {Observable} from 'rxjs';
import {PoComponent} from './po.component';
import {PrintComponent} from './print.component';
import {LineitemListComponent} from '../lineitem/lineitem-list.component';
import {LineitemDetailComponent} from '../lineitem/detail.component';
import {LineitemCopiesComponent} from '../lineitem/copies.component';
import {BriefRecordComponent} from '../lineitem/brief-record.component';
import {CreateAssetsComponent} from '../lineitem/create-assets.component';
import {LineitemHistoryComponent} from '../lineitem/history.component';
import {LineitemWorksheetComponent} from '../lineitem/worksheet.component';
import {PoHistoryComponent} from './history.component';
import {PoEdiMessagesComponent} from './edi.component';
import {PoCreateComponent} from './create.component';

// following example of https://www.concretepage.com/angular-2/angular-candeactivate-guard-example
export interface PoChildDeactivationGuarded {
    canDeactivate(): Observable<boolean> | Promise<boolean> | boolean;
}

@Injectable()
export class CanLeavePoChildGuard implements CanDeactivate<PoChildDeactivationGuarded> {
    canDeactivate(component: PoChildDeactivationGuarded):  Observable<boolean> | Promise<boolean> | boolean {
        return component.canDeactivate ? component.canDeactivate() : true;
    }
}

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
        path: 'create-assets',
        component: CreateAssetsComponent
    }, {
        path: 'lineitem/:lineitemId/detail',
        component: LineitemDetailComponent
    }, {
        path: 'lineitem/:lineitemId/history',
        component: LineitemHistoryComponent
    }, {
        path: 'lineitem/:lineitemId/items',
        component: LineitemCopiesComponent,
        canDeactivate: [CanLeavePoChildGuard]
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
    providers: [CanLeavePoChildGuard]
})

export class PoRoutingModule {}
