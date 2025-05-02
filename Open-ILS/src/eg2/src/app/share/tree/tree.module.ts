import {NgModule} from '@angular/core';
import {EgCommonModule} from '@eg/common.module';
import {TreeComponent} from './tree.component';
import {TreeMultiselectComponent} from './tree-multiselect.component';

@NgModule({
    declarations: [
        TreeComponent,
        TreeMultiselectComponent
    ],
    imports: [
        EgCommonModule
    ],
    exports: [
        TreeComponent,
        TreeMultiselectComponent
    ],
    providers: [
    ]
})

export class TreeModule {}

