/*
  Module for grouping commonly used widgets that might be embedded
  in other shared components. Components included here should be
  unlikely to ever need to embed one another.
*/
import {NgModule, ModuleWithProviders} from '@angular/core';
import {CommonModule} from '@angular/common';
import {FormsModule} from '@angular/forms';
import {NgbModule} from '@ng-bootstrap/ng-bootstrap';
import {ComboboxComponent} from '@eg/share/combobox/combobox.component';
import {ComboboxEntryComponent} from '@eg/share/combobox/combobox-entry.component';
import {DateSelectComponent} from '@eg/share/date-select/date-select.component';
import {OrgSelectComponent} from '@eg/share/org-select/org-select.component';

@NgModule({
  declarations: [
    ComboboxComponent,
    ComboboxEntryComponent,
    DateSelectComponent,
    OrgSelectComponent
  ],
  imports: [
    CommonModule,
    FormsModule,
    NgbModule
  ],
  exports: [
    CommonModule,
    FormsModule,
    NgbModule,
    ComboboxComponent,
    ComboboxEntryComponent,
    DateSelectComponent,
    OrgSelectComponent
  ],
})

export class CommonWidgetsModule { }
