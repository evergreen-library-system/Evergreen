import {NgModule} from '@angular/core';
import {StaffCommonModule} from '@eg/staff/common.module';
import {BibListComponent} from './bib-list.component';

@NgModule({
    imports: [
        BibListComponent,
        StaffCommonModule
    ],
    exports: [
        BibListComponent
    ],
    providers: [
    ]
})

export class BibListModule {}

