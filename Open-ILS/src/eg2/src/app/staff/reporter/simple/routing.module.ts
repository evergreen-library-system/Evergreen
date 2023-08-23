import {NgModule} from '@angular/core';
import {RouterModule, Routes, RouterStateSnapshot, ActivatedRouteSnapshot} from '@angular/router';
import {SimpleReporterComponent} from './simple-reporter.component';
import {SREditorComponent} from './sr-editor.component';
import {SimpleReporterServiceResolver} from '../share/reporter.service';

const routes: Routes = [
    { path: '',
        component: SimpleReporterComponent,
        resolve: { srSvcResolver: SimpleReporterServiceResolver },
    },
    { path: 'new',
        component: SREditorComponent,
        resolve: { srSvcResolver: SimpleReporterServiceResolver },
        canDeactivate: ['canLeaveEditor'],
        runGuardsAndResolvers: 'always'
    },
    { path: 'edit/:id',
        component: SREditorComponent,
        resolve: { srSvcResolver: SimpleReporterServiceResolver },
        canDeactivate: ['canLeaveEditor'],
        runGuardsAndResolvers: 'always'
    },
];

@NgModule({
    imports: [RouterModule.forChild(routes)],
    exports: [RouterModule],
    providers: [SimpleReporterServiceResolver,
        {
            provide: 'canLeaveEditor',
            useValue: (component: SREditorComponent, currentRoute: ActivatedRouteSnapshot,
                currentState: RouterStateSnapshot, nextState: RouterStateSnapshot) => component.canLeaveEditor()
        }
    ]
})

export class SimpleReporterRoutingModule {
}

