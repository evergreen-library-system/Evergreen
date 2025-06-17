import { NgModule } from '@angular/core';
import { RouterModule } from '@angular/router';
import { RecordBucketComponent } from './record-bucket.component';
import { RecordBucketItemComponent } from './record-bucket-item.component';
import { getBucketRoutes } from '@eg/staff/share/buckets/bucket-routing.module';

@NgModule({
    imports: [RouterModule.forChild(getBucketRoutes(
        RecordBucketComponent, 
        RecordBucketItemComponent
    ))],
    exports: [RouterModule]
})
export class RecordBucketRoutingModule {}
