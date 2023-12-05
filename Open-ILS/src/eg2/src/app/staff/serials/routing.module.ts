import { NgModule } from '@angular/core';
import { RouterModule, Routes } from '@angular/router';
import { QuickReceiveComponent } from './quick-receive.component';

const routes: Routes = [{
    path: ':bibRecordId/quick-receive',
    component: QuickReceiveComponent
}];

@NgModule({
    imports: [RouterModule.forChild(routes)],
    exports: [RouterModule]
})
export class SerialsRoutingModule { }
