import {NgModule} from '@angular/core';
import {RouterModule, Routes} from '@angular/router';
import {HoldsPullListComponent} from './pull-list.component';

const routes: Routes = [{
    path: 'pull-list',
    component: HoldsPullListComponent
}];

@NgModule({
    imports: [RouterModule.forChild(routes)],
    exports: [RouterModule]
})

export class HoldsUiRoutingModule {}
