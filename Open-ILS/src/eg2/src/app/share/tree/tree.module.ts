import {NgModule} from '@angular/core';
import {EgCommonModule} from '@eg/common.module';
import {TreeComponent} from './tree.component';
import {TreeMultiselectComponent} from './tree-multiselect.component';

@NgModule({
    imports: [
        EgCommonModule,
        TreeComponent,
        TreeMultiselectComponent
    ],
    exports: [
        TreeComponent,
        TreeMultiselectComponent
    ]
})

export class TreeModule {}

