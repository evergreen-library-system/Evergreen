import {NgModule} from '@angular/core';
import {RouterModule, Routes} from '@angular/router';
import {FundsComponent} from './funds.component';

const routes: Routes = [{
    path: '',
    component: FundsComponent
}, {
    path: ':tab/:id',
    component: FundsComponent
}];

@NgModule({
    imports: [RouterModule.forChild(routes)],
    exports: [RouterModule]
})

export class FundsRoutingModule {}
