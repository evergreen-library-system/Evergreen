import {NgModule} from '@angular/core';
import {StaffCommonModule} from '@eg/staff/common.module';
import {CatRoutingModule} from './routing.module';
import {BibByIdentComponent} from './bib-by-ident.component';
import {Z3950SearchModule} from '@eg/staff/share/z3950-search/z3950-search.module';

@NgModule({
    declarations: [
        BibByIdentComponent
    ],
    imports: [
        StaffCommonModule,
        Z3950SearchModule,
        CatRoutingModule
    ],
    providers: [
    ]
})

export class CatModule {
}
