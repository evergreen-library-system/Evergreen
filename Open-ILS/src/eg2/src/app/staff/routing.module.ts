import {NgModule} from '@angular/core';
import {RouterModule, Routes} from '@angular/router';
import {StaffResolver} from './resolver.service';
import {StaffComponent} from './staff.component';
import {StaffMFAComponent} from './mfa.component';
import {StaffLoginComponent} from './login.component';
import {StaffLoginNotAllowedComponent} from './login-not-allowed.component';
import {StaffSplashComponent} from './splash.component';
import {AboutComponent} from './about.component';

// Not using 'canActivate' because it's called before all resolvers,
// even the parent resolver, but the resolvers parse the IDL, load settings,
// etc.  Chicken, meet egg.

const routes: Routes = [{
    path: '',
    component: StaffComponent,
    resolve: {staffResolver : StaffResolver},
    children: [{
        path: '',
        redirectTo: 'splash',
        pathMatch: 'full',
    }, {
        path: 'acq',
        loadChildren: () =>
            import('@eg/staff/acq/routing.module').then(m => m.AcqRoutingModule)
    }, {
        path: 'booking',
        loadChildren: () =>
            import('./booking/booking.module').then(m => m.BookingModule)
    }, {
        path: 'about',
        component: AboutComponent
    }, {
        path: 'login',
        component: StaffLoginComponent
    }, {
        path: 'mfa',
        component: StaffMFAComponent
    }, {
    // Attempt to login to the staff client w/o the needed permissions
    // or work org unit.
        path: 'login-not-allowed',
        component: StaffLoginNotAllowedComponent
    }, {
    // Attempt to fetch a specific page the user does not have
    // access to.
        path: 'no_permission',
        component: StaffSplashComponent
    }, {
        path: 'splash',
        component: StaffSplashComponent
    }, {
        path: 'circ',
        loadChildren: () =>
            import('./circ/routing.module').then(m => m.CircRoutingModule)
    }, {
        path: 'cat',
        loadChildren: () =>
            import('./cat/cat.module').then(m => m.CatModule)
    }, {
        path: 'catalog',
        loadChildren: () =>
            import('./catalog/catalog.module').then(m => m.CatalogModule)
    }, {
        path: 'reporter',
        loadChildren: () =>
            import('@eg/staff/reporter/routing.module').then(m => m.ReporterRoutingModule)
    }, {
        path: 'sandbox',
        loadChildren: () =>
            import('./sandbox/sandbox.module').then(m => m.SandboxModule)
    }, {
        path: 'hopeless',
        loadChildren: () =>
            import('@eg/staff/hopeless/hopeless.module').then(m => m.HopelessModule)
    }, {
        path: 'admin',
        loadChildren: () =>
            import('./admin/routing.module').then(m => m.AdminRoutingModule)
    }, {
        path: 'serials',
        loadChildren: () =>
            import('./serials/routing.module').then(m => m.SerialsRoutingModule)
    }]
}];

@NgModule({
    imports: [RouterModule.forChild(routes)],
    exports: [RouterModule],
    providers: [StaffResolver]
})

export class StaffRoutingModule {}

