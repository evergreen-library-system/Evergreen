import {NgModule} from '@angular/core';
import {RouterModule, Routes} from '@angular/router';
import {CSAuthorityFieldsComponent} from './control-set-authority-fields.component';

const routes: Routes = [{
    path: '',
    component: CSAuthorityFieldsComponent
}];

@NgModule({
    imports: [RouterModule.forChild(routes)],
    exports: [RouterModule]
})

export class CSAuthorityFieldsRoutingModule {}
