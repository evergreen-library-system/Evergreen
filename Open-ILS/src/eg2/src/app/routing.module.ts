import {NgModule} from '@angular/core';
import {RouterModule, Routes} from '@angular/router';
import {BaseResolver} from './resolver.service';
import {WelcomeComponent} from './welcome.component';

/**
 * Avoid loading all application JS up front by lazy-loading sub-modules.
 * When lazy loading, no module references should be directly imported.
 * The refs are encoded in the loadChildren attribute of each route.
 * These modules are encoded as separate JS chunks that are fetched
 * from the server only when needed.
 */
const routes: Routes = [{
    path: '',
    component: WelcomeComponent
  }, {
    path: 'staff',
    resolve : {startup : BaseResolver},
    loadChildren: () => import('./staff/staff.module').then(m => m.StaffModule)
  }, {
    path: 'staff/scko',
    resolve : {startup : BaseResolver},
    loadChildren: () => import('./staff/scko/scko.module').then(m => m.SckoModule)
}];

@NgModule({
    imports: [RouterModule.forRoot(routes, {
        onSameUrlNavigation: 'reload'
    })],
    exports: [RouterModule],
    providers: [BaseResolver]
})

export class BaseRoutingModule {}
