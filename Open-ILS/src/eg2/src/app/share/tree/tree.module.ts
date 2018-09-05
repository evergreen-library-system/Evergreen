import {NgModule} from '@angular/core';
import {EgCommonModule} from '@eg/common.module';
import {TreeComponent} from './tree.component';

@NgModule({
    declarations: [
        TreeComponent
    ],
    imports: [
        EgCommonModule
    ],
    exports: [
        TreeComponent
    ],
    providers: [
    ]
})

export class TreeModule {}

