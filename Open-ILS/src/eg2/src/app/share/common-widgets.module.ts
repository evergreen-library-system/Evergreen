/*
  Module for grouping commonly used widgets that might be embedded
  in other shared components. Components included here should be
  unlikely to ever need to embed one another.
*/
import {NgModule, ModuleWithProviders} from '@angular/core';
import {CommonModule} from '@angular/common';
import {FormsModule, ReactiveFormsModule} from '@angular/forms';
import {NgbModule} from '@ng-bootstrap/ng-bootstrap';
import {EgCoreModule} from '@eg/core/core.module';
import {ComboboxComponent} from '@eg/share/combobox/combobox.component';
import {ComboboxEntryComponent} from '@eg/share/combobox/combobox-entry.component';
import {DateSelectComponent} from '@eg/share/date-select/date-select.component';
import {OrgSelectComponent} from '@eg/share/org-select/org-select.component';
import {DateRangeSelectComponent} from '@eg/share/daterange-select/daterange-select.component';
import {DateTimeSelectComponent} from '@eg/share/datetime-select/datetime-select.component';
import {ContextMenuModule} from '@eg/share/context-menu/context-menu.module';


@NgModule({
  declarations: [
    ComboboxComponent,
    ComboboxEntryComponent,
    DateSelectComponent,
    OrgSelectComponent,
    DateRangeSelectComponent,
    DateTimeSelectComponent
  ],
  imports: [
    CommonModule,
    FormsModule,
    ReactiveFormsModule,
    NgbModule,
    EgCoreModule,
    ContextMenuModule
  ],
  exports: [
    CommonModule,
    FormsModule,
    NgbModule,
    EgCoreModule,
    ComboboxComponent,
    ComboboxEntryComponent,
    DateSelectComponent,
    OrgSelectComponent,
    DateRangeSelectComponent,
    DateTimeSelectComponent,
    ContextMenuModule
  ]
})

export class CommonWidgetsModule { }
