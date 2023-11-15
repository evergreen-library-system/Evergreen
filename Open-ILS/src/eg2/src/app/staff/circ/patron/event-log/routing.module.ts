import {NgModule} from '@angular/core';
import {RouterModule, Routes} from '@angular/router';
import {EventLogComponent} from './event-log.component';

const routes: Routes = [
    { path: '',
        component: EventLogComponent
    },
    { path: ':patron',
        component: EventLogComponent
    },
];

@NgModule({
    imports: [RouterModule.forChild(routes)],
    exports: [RouterModule]
})

export class EventLogRoutingModule {}
