import {NgModule} from '@angular/core';
import {CommonModule} from '@angular/common';
import {StaffCommonModule} from '@eg/staff/common.module';
import {AdminPageModule} from '@eg/staff/share/admin-page/admin-page.module';
import {PatronModule} from '@eg/staff/share/patron/patron.module';
import {FmRecordEditorModule} from '@eg/share/fm-editor/fm-editor.module';
import {BucketTransferDialogComponent} from '@eg/staff/share/buckets/bucket-transfer-dialog.component';
import {BucketShareDialogComponent} from '@eg/staff/share/buckets/bucket-share-dialog.component';
import {BucketUserShareComponent} from '@eg/staff/share/buckets/bucket-user-share.component';
import {TreeModule} from '@eg/share/tree/tree.module';
import {BucketActionSummaryDialogComponent} from '@eg/staff/share/buckets/bucket-action-summary-dialog.component';
import {RecordBucketComponent} from '@eg/staff/share/buckets/record-bucket.component';
import {RecordBucketExportDialogComponent} from '@eg/staff/share/buckets/record-bucket-export-dialog.component';
import {RecordBucketItemUploadDialogComponent} from '@eg/staff/share/buckets/record-bucket-item-upload-dialog.component';
import {RecordBucketItemComponent} from '@eg/staff/share/buckets/record-bucket-item.component';
import {RecordBucketRoutingModule} from './record-bucket-routing.module';
import {HoldsModule} from '@eg/staff/share/holds/holds.module';

@NgModule({
    declarations: [
        BucketTransferDialogComponent,
        BucketShareDialogComponent,
        BucketUserShareComponent,
        BucketActionSummaryDialogComponent,
        RecordBucketComponent,
        RecordBucketExportDialogComponent,
        RecordBucketItemUploadDialogComponent,
        RecordBucketItemComponent
    ],
    imports: [
        StaffCommonModule,
        AdminPageModule,
        PatronModule,
        HoldsModule,
        FmRecordEditorModule,
        TreeModule,
        RecordBucketRoutingModule
    ],
    exports: [
        BucketTransferDialogComponent,
        BucketShareDialogComponent,
        BucketUserShareComponent,
        BucketActionSummaryDialogComponent,
        RecordBucketComponent,
        RecordBucketExportDialogComponent,
        RecordBucketItemUploadDialogComponent,
        RecordBucketItemComponent
    ],
    providers: [
    ]
})

export class RecordBucketModule {
}
