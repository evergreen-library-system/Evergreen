import {NgModule} from '@angular/core';
import {RouterModule, Routes} from '@angular/router';
import {OrgUnitSettingsComponent} from './org-unit-settings.component';

const routes: Routes = [{
    path: '',
    component: OrgUnitSettingsComponent
}];

@NgModule({
    imports: [RouterModule.forChild(routes)],
    exports: [RouterModule]
})

export class OrgUnitSettingsRoutingModule {}
