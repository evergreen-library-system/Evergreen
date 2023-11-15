import {NgModule} from '@angular/core';
import {RouterModule, Routes} from '@angular/router';
import {ItemEventLogComponent} from './event-log.component';

const routes: Routes = [
    { path: '',
        component: ItemEventLogComponent
    },
    { path: ':item',
        component: ItemEventLogComponent
    },
];

@NgModule({
    imports: [RouterModule.forChild(routes)],
    exports: [RouterModule]
})

export class ItemEventLogRoutingModule {}
