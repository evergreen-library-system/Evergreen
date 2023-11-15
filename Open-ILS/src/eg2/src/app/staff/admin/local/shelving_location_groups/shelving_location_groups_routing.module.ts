import {NgModule} from '@angular/core';
import {RouterModule, Routes} from '@angular/router';
import {ShelvingLocationGroupsComponent} from './shelving_location_groups.component';

const routes: Routes = [{
    path: '',
    component: ShelvingLocationGroupsComponent
}];

@NgModule({
    imports: [RouterModule.forChild(routes)],
    exports: [RouterModule]
})

export class ShelvingLocationGroupsRoutingModule {}
