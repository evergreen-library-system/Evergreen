import {NgModule} from '@angular/core';
import {RouterModule, Routes} from '@angular/router';
import {SearchFilterGroupComponent} from './search-filter-group.component';
import {SearchFilterGroupEntriesComponent} from './search-filter-group-entries.component';

const routes: Routes = [{
    path: ':id',
    component: SearchFilterGroupEntriesComponent
}, {
    path: '',
    component: SearchFilterGroupComponent
}];

@NgModule({
    imports: [RouterModule.forChild(routes)],
    exports: [RouterModule]
})

export class SearchFilterGroupRoutingModule {}
