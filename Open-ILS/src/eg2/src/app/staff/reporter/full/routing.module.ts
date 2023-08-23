import {NgModule} from '@angular/core';
import {RouterModule, Routes, RouterStateSnapshot, ActivatedRouteSnapshot} from '@angular/router';
import {FullReporterComponent} from './reporter.component';
import {FullReporterEditorComponent} from './editor.component';
import {FullReporterDefinitionComponent} from './definition.component';
import {FullReporterServiceResolver} from '../share/reporter.service';

const routes: Routes = [
    { path: '',
        component: FullReporterComponent,
        resolve: { RSvcResolver: FullReporterServiceResolver },
    },
    { path: 'new',
        component: FullReporterEditorComponent,
        resolve: { RSvcResolver: FullReporterServiceResolver },
        canDeactivate: ['canLeaveEditor'],
        runGuardsAndResolvers: 'always'
    },
    { path: 'new/:folder',
        component: FullReporterEditorComponent,
        resolve: { RSvcResolver: FullReporterServiceResolver },
        canDeactivate: ['canLeaveEditor'],
        runGuardsAndResolvers: 'always'
    },
    { path: 'edit/:id',
        component: FullReporterEditorComponent,
        resolve: { RSvcResolver: FullReporterServiceResolver },
        canDeactivate: ['canLeaveEditor'],
        runGuardsAndResolvers: 'always'
    },
    { path: 'edit/:id/:folder',
        component: FullReporterEditorComponent,
        resolve: { RSvcResolver: FullReporterServiceResolver },
        canDeactivate: ['canLeaveEditor'],
        runGuardsAndResolvers: 'always'
    },
    { path: 'clone/:id',
        component: FullReporterEditorComponent,
        resolve: { RSvcResolver: FullReporterServiceResolver },
        canDeactivate: ['canLeaveEditor'],
        runGuardsAndResolvers: 'always'
    },
    { path: 'clone/:id/:folder',
        component: FullReporterEditorComponent,
        resolve: { RSvcResolver: FullReporterServiceResolver },
        canDeactivate: ['canLeaveEditor'],
        runGuardsAndResolvers: 'always'
    },
    { path: 'define/new/:t_id',
        component: FullReporterDefinitionComponent,
        resolve: { RSvcResolver: FullReporterServiceResolver },
        canDeactivate: ['canLeaveEditor'],
        runGuardsAndResolvers: 'always'
    },
    { path: 'define/clone/:r_id',
        component: FullReporterDefinitionComponent,
        resolve: { RSvcResolver: FullReporterServiceResolver },
        canDeactivate: ['canLeaveEditor'],
        runGuardsAndResolvers: 'always'
    },
    { path: 'define/edit/:r_id',
        component: FullReporterDefinitionComponent,
        resolve: { RSvcResolver: FullReporterServiceResolver },
        canDeactivate: ['canLeaveEditor'],
        runGuardsAndResolvers: 'always'
    },
    { path: 'define/view/:r_id',
        component: FullReporterDefinitionComponent,
        resolve: { RSvcResolver: FullReporterServiceResolver },
        canDeactivate: ['canLeaveEditor'],
        runGuardsAndResolvers: 'always'
    },
];

@NgModule({
    imports: [RouterModule.forChild(routes)],
    exports: [RouterModule],
    providers: [FullReporterServiceResolver,
        {
            provide: 'canLeaveEditor',
            useValue: (component: FullReporterEditorComponent, currentRoute: ActivatedRouteSnapshot,
                currentState: RouterStateSnapshot, nextState: RouterStateSnapshot) => component.canLeaveEditor()
        }
    ]
})

export class FullReporterRoutingModule {
}

