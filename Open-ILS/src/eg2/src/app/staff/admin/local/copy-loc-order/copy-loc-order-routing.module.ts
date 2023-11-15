import {NgModule} from '@angular/core';
import {RouterModule, Routes} from '@angular/router';
import {CopyLocOrderComponent} from './copy-loc-order.component';

const routes: Routes = [{
    path: '',
    component: CopyLocOrderComponent
}];

@NgModule({
    imports: [RouterModule.forChild(routes)],
    exports: [RouterModule]
})

export class CopyLocOrderRoutingModule {}
