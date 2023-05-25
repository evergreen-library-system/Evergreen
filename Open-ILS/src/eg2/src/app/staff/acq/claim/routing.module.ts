import {NgModule} from '@angular/core';
import {RouterModule, Routes} from '@angular/router';
// import {LineitemListComponent} from '../lineitem/lineitem-list.component';
// import {LineitemDetailComponent} from '../lineitem/detail.component';
// import {LineitemCopiesComponent} from '../lineitem/copies.component';
// import {BriefRecordComponent} from '../lineitem/brief-record.component';
// import {LineitemHistoryComponent} from '../lineitem/history.component';
// import {LineitemWorksheetComponent} from '../lineitem/worksheet.component';
import {ClaimEligibleListComponent} from './list.component';

const routes: Routes = [{
    path: '',
    component: ClaimEligibleListComponent
}];

@NgModule({
    imports: [RouterModule.forChild(routes)],
    exports: [RouterModule],
    providers: []
})

export class ClaimRoutingModule {}
