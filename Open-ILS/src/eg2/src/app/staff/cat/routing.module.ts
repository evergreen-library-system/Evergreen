import {NgModule} from '@angular/core';
import {RouterModule, Routes} from '@angular/router';
import {BibByIdentComponent} from './bib-by-ident.component';
import {Z3950SearchComponent} from '@eg/staff/share/z3950-search/z3950-search.component';

const routes: Routes = [
    { path: 'vandelay',
        loadChildren: () =>
            import('./vandelay/vandelay.module').then(m => m.VandelayModule)
    }, {
        path: 'authority',
        loadChildren: () =>
            import('./authority/authority.module').then(m => m.AuthorityModule)
    }, {
        path: 'linkchecker',
        loadChildren: () =>
            import('./linkchecker/linkchecker.module').then(m => m.LinkCheckerModule)
    }, {
        path: 'marcbatch',
        loadChildren: () =>
            import('./marcbatch/marcbatch.module').then(m => m.MarcBatchModule)
    }, {
        path: 'item',
        loadChildren: () => import('./item/item.module').then(m => m.ItemModule)
    }, {
        path: 'volcopy',
        loadChildren: () =>
            import('./volcopy/volcopy.module').then(m => m.VolCopyModule)
    }, {
        path: 'bib-from/:identType',
        component: BibByIdentComponent
    }, {
        path: 'z3950/search',
        component: Z3950SearchComponent
    }
];

@NgModule({
    imports: [RouterModule.forChild(routes)],
    exports: [RouterModule]
})

export class CatRoutingModule {}
