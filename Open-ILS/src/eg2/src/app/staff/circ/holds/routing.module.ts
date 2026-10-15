import {NgModule} from '@angular/core';
import {RouterModule, Routes} from '@angular/router';
import {HoldsPullListComponent} from './pull-list.component';
import {HoldGroupsComponent} from './hold-groups/hold-groups.component';

const routes: Routes = [{
    path: 'pull-list',
    component: HoldsPullListComponent
}, {
    path: 'hold-groups',
    component: HoldGroupsComponent,
    children: [
        {
            path: ':tab',
            component: HoldGroupsComponent
        }, {
            path: ':tab/:id',
            component: HoldGroupsComponent
        }
    ]
}
];

@NgModule({
    imports: [RouterModule.forChild(routes)],
    exports: [RouterModule]
})

export class HoldsUiRoutingModule {}
