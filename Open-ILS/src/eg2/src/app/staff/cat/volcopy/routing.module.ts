import {NgModule} from '@angular/core';
import {RouterModule, Routes} from '@angular/router';
import {VolCopyComponent} from './volcopy.component';
import {CanDeactivateGuard} from '@eg/share/util/can-deactivate.guard';

const routes: Routes = [{
    path: ':tab/:target/:target_id',
    component: VolCopyComponent,
    canDeactivate: [CanDeactivateGuard]
}];

@NgModule({
    imports: [RouterModule.forChild(routes)],
    exports: [RouterModule],
    providers: []
})

export class VolCopyRoutingModule {}

