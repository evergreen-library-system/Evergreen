import {NgModule} from '@angular/core';
import {RouterModule, Routes} from '@angular/router';

const routes: Routes = [
    { path: 'simple',
        loadChildren: () =>
            import('./simple/simple-reporter.module').then(m => m.SimpleReporterModule)
    }
];

@NgModule({
    imports: [RouterModule.forChild(routes)],
    exports: [RouterModule]
})

export class ReporterRoutingModule {
}

