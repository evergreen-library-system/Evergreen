import {NgModule} from '@angular/core';
import {RouterModule, Routes} from '@angular/router';
import {VolCopyTemplateGridComponent} from './template-grid.component';
import {VolCopyTemplateEditComponent} from './template-edit.component';
import {VolCopyComponent} from './volcopy.component';
import {CanDeactivateGuard} from '@eg/share/util/can-deactivate.guard';

const routes: Routes = [{
    path: 'template_grid',
    component: VolCopyTemplateGridComponent,
    canDeactivate: [CanDeactivateGuard]
},{
    path: 'template',
    component: VolCopyTemplateEditComponent,
    canDeactivate: [CanDeactivateGuard]
},{
    path: 'template/:target',
    component: VolCopyTemplateEditComponent,
    canDeactivate: [CanDeactivateGuard]
},{
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

