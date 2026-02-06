import {Component} from '@angular/core';
import { FmRecordEditorComponent } from '@eg/share/fm-editor/fm-editor.component';
import { StaffCommonModule } from '@eg/staff/common.module';
import { AdminPageComponent } from '@eg/staff/share/admin-page/admin-page.component';

@Component({
    templateUrl: './circ_limit_set.component.html',
    imports: [
        AdminPageComponent,
        FmRecordEditorComponent,
        StaffCommonModule
    ]
})

export class CircLimitSetComponent { }
