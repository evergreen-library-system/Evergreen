import {NgModule} from '@angular/core';
import {StaffCommonModule} from '@eg/staff/common.module';
import {CatRoutingModule} from './routing.module';
import {BibByIdentComponent} from './bib-by-ident.component';

@NgModule({
  declarations: [
    BibByIdentComponent
  ],
  imports: [
    StaffCommonModule,
    CatRoutingModule
  ],
  providers: [
  ]
})

export class CatModule {
}
