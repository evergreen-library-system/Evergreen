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
import {ButtonStyleDirective} from '@eg/share/util/button-style.directive';
import {ComboboxComponent, IdlClassTemplateDirective} from '@eg/share/combobox/combobox.component';
import {ComboboxEntryComponent} from '@eg/share/combobox/combobox-entry.component';
import {DateSelectComponent} from '@eg/share/date-select/date-select.component';
import {BooleanSelectComponent} from '@eg/share/boolean-select/boolean-select.component';
import {OrgSelectComponent} from '@eg/share/org-select/org-select.component';
import {DepthSelectComponent} from '@eg/share/depth-select/depth-select.component';
import {DateRangeSelectComponent} from '@eg/share/daterange-select/daterange-select.component';
import {DateTimeSelectComponent} from '@eg/share/datetime-select/datetime-select.component';
import {ContextMenuModule} from '@eg/share/context-menu/context-menu.module';
import {FileReaderComponent} from '@eg/share/file-reader/file-reader.component';
import {IntervalInputComponent} from '@eg/share/interval-input/interval-input.component';
import {ClipboardDialogComponent} from '@eg/share/clipboard/clipboard-dialog.component';
import { CredentialInputComponent } from './util/credential-input.component';


@NgModule({
    declarations: [
        ButtonStyleDirective,
        ComboboxComponent,
        ComboboxEntryComponent,
        DateSelectComponent,
        BooleanSelectComponent,
        OrgSelectComponent,
        DepthSelectComponent,
        DateRangeSelectComponent,
        DateTimeSelectComponent,
        FileReaderComponent,
        ClipboardDialogComponent,
        IdlClassTemplateDirective,
        IntervalInputComponent,
        CredentialInputComponent
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
        ButtonStyleDirective,
        ComboboxComponent,
        ComboboxEntryComponent,
        DateSelectComponent,
        BooleanSelectComponent,
        OrgSelectComponent,
        DepthSelectComponent,
        DateRangeSelectComponent,
        DateTimeSelectComponent,
        ClipboardDialogComponent,
        ContextMenuModule,
        FileReaderComponent,
        IntervalInputComponent,
        CredentialInputComponent
    ],
})

export class CommonWidgetsModule { }
