import { NgModule } from '@angular/core';
import { RouterModule, Routes } from '@angular/router';
import { RecordBucketComponent } from './record-bucket.component';
import { RecordBucketItemComponent } from './record-bucket-item.component';

const routes: Routes = [
    { path: '', component: RecordBucketComponent },
    { path: 'admin', component: RecordBucketComponent },
    { path: 'all', component: RecordBucketComponent },
    { path: 'user', component: RecordBucketComponent },
    { path: 'favorites', component: RecordBucketComponent },
    { path: 'recent', component: RecordBucketComponent },
    { path: 'shared-with-others', component: RecordBucketComponent },
    { path: 'shared-with-user', component: RecordBucketComponent },
    { path: 'bucket/:id', component: RecordBucketItemComponent },
    { path: 'content/:id', component: RecordBucketItemComponent },
    { path: ':id', component: RecordBucketComponent }
];

@NgModule({
    imports: [RouterModule.forChild(routes)],
    exports: [RouterModule]
})
export class RecordBucketRoutingModule {}
