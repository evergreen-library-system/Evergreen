import {NgModule} from '@angular/core';
import {RouterModule, Routes} from '@angular/router';

const routes: Routes = [
    { path: 'event-log',
        loadChildren: () =>
            import('./event-log/event-log.module').then(m => m.ItemEventLogModule)
    }
];

@NgModule({
    imports: [RouterModule.forChild(routes)],
    exports: [RouterModule]
})

export class CircItemRoutingModule {}
