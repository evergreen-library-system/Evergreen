import {NgModule} from '@angular/core';
import {RouterModule, Routes} from '@angular/router';
import {LinkCheckerComponent} from './linkchecker.component';
import {LinkCheckerUrlsComponent} from './urls.component';
import {LinkCheckerAttemptsComponent} from './attempts.component';

const routes: Routes = [{
    path: '',
    component: LinkCheckerComponent
}, {
    path: 'urls',
    component: LinkCheckerUrlsComponent
}, {
    path: 'attempts',
    component: LinkCheckerAttemptsComponent
}];

@NgModule({
    imports: [RouterModule.forChild(routes)],
    exports: [RouterModule],
    providers: []
})

export class LinkCheckerRoutingModule {}

