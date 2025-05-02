import {NgModule} from '@angular/core';
import {RouterModule, Routes} from '@angular/router';
import {MarkItemMissingPiecesComponent} from './missing-pieces.component';
import {CopyAlertsPageComponent} from '@eg/staff/share/holdings/copy-alerts-page.component';

const routes: Routes = [{
    path: 'missing_pieces',
    component: MarkItemMissingPiecesComponent
}, {
    path: 'missing_pieces/:id',
    component: MarkItemMissingPiecesComponent
}, {
    path: 'alerts',
    component: CopyAlertsPageComponent
}];

@NgModule({
    imports: [RouterModule.forChild(routes)],
    exports: [RouterModule],
    providers: []
})

export class ItemRoutingModule {}

