import {NgModule} from '@angular/core';
import {AdminCommonModule} from '@eg/staff/admin/common.module';
import {TriggersComponent} from './triggers.component';
import {TriggersRoutingModule} from './triggers_routing.module';
import {EditEventDefinitionComponent} from './trigger-edit.component';

@NgModule({
    declarations: [
        TriggersComponent,
        EditEventDefinitionComponent
    ],
    imports: [
        AdminCommonModule,
        TriggersRoutingModule,
    ],
    exports: [
    ],
    providers: [
    ]
})

export class TriggersModule {
}
