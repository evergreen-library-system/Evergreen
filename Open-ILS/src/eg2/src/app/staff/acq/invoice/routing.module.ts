import {NgModule} from '@angular/core';
import {RouterModule, Routes} from '@angular/router';
import {CanDeactivateGuard} from '@eg/share/util/can-deactivate.guard';
import {InvoiceComponent} from './invoice.component';
import {AttrDefsResolver} from '../search/resolver.service';
import {AttrDefsService} from '../search/attr-defs.service';

const routes: Routes = [{
    path: 'create',
    component: InvoiceComponent,
    canDeactivate: [CanDeactivateGuard]
}, {
    path: ':invoiceId',
    component: InvoiceComponent,
    canDeactivate: [CanDeactivateGuard],
}];

@NgModule({
    imports: [RouterModule.forChild(routes)],
    exports: [RouterModule],
    providers: [AttrDefsResolver, AttrDefsService]
})

export class InvoiceRoutingModule {}
