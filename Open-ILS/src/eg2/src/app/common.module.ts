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

import {HtmlToTxtService} from '@eg/share/util/htmltotxt.service';
import {PrintService} from '@eg/share/print/print.service';
import {AnonCacheService} from '@eg/share/util/anon-cache.service';

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
import {StringModule} from '@eg/share/string/string.module';


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
    BoolDisplayComponent
  ],
  imports: [
    CommonModule,
    FormsModule,
    ReactiveFormsModule,
    RouterModule,
    NgbModule,
    EgCoreModule,
    StringModule
  ],
  exports: [
    CommonModule,
    RouterModule,
    NgbModule,
    FormsModule,
    EgCoreModule,
    StringModule,
    ReactiveFormsModule,
    PrintComponent,
    DialogComponent,
    AlertDialogComponent,
    ConfirmDialogComponent,
    PromptDialogComponent,
    ProgressInlineComponent,
    ProgressDialogComponent,
    BoolDisplayComponent,
    ToastComponent
  ]
})

export class EgCommonModule {
    /** forRoot() lets us define services that should only be
     * instantiated once for all loaded routes */
    static forRoot(): ModuleWithProviders {
        return {
            ngModule: EgCommonModule,
            providers: [
                AnonCacheService,
                HtmlToTxtService,
                PrintService,
                ToastService
            ]
        };
    }
}

