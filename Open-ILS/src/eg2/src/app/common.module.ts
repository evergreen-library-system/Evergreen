/**
 * Modules, services, and components used by all apps.
 */
import {CommonModule} from '@angular/common';
import {NgModule, ModuleWithProviders} from '@angular/core';
import {RouterModule} from '@angular/router';
import {FormsModule, ReactiveFormsModule} from '@angular/forms';
import {NgbModule} from '@ng-bootstrap/ng-bootstrap';
import {EgCoreModule} from '@eg/core/core.module';

/*
Note core services are injected into 'root'.
They do not have to be added to the providers list.
*/

// consider moving these to core...
import {HatchService} from '@eg/share/print/hatch.service';
import {PrintService} from '@eg/share/print/print.service';

// Globally available components
import {PrintComponent} from '@eg/share/print/print.component';
import {DialogComponent} from '@eg/share/dialog/dialog.component';
import {AlertDialogComponent} from '@eg/share/dialog/alert.component';
import {ConfirmDialogComponent} from '@eg/share/dialog/confirm.component';
import {PromptDialogComponent} from '@eg/share/dialog/prompt.component';
import {ProgressInlineComponent} from '@eg/share/dialog/progress-inline.component';
import {ProgressDialogComponent} from '@eg/share/dialog/progress.component';
import {BoolDisplayComponent} from '@eg/share/util/bool.component';
import {ToastService} from '@eg/share/toast/toast.service';
import {ToastComponent} from '@eg/share/toast/toast.component';
import {StringComponent} from '@eg/share/string/string.component';
import {StringService} from '@eg/share/string/string.service';


@NgModule({
  declarations: [
    PrintComponent,
    DialogComponent,
    AlertDialogComponent,
    ConfirmDialogComponent,
    PromptDialogComponent,
    ProgressInlineComponent,
    ProgressDialogComponent,
    ToastComponent,
    StringComponent,
    BoolDisplayComponent
  ],
  imports: [
    CommonModule,
    FormsModule,
    ReactiveFormsModule,
    RouterModule,
    NgbModule,
    EgCoreModule
  ],
  exports: [
    CommonModule,
    RouterModule,
    NgbModule,
    FormsModule,
    EgCoreModule,
    ReactiveFormsModule,
    PrintComponent,
    DialogComponent,
    AlertDialogComponent,
    ConfirmDialogComponent,
    PromptDialogComponent,
    ProgressInlineComponent,
    ProgressDialogComponent,
    BoolDisplayComponent,
    ToastComponent,
    StringComponent
  ]
})

export class EgCommonModule {
    /** forRoot() lets us define services that should only be
     * instantiated once for all loaded routes */
    static forRoot(): ModuleWithProviders {
        return {
            ngModule: EgCommonModule,
            providers: [
                HatchService,
                PrintService,
                StringService,
                ToastService
            ]
        };
    }
}

