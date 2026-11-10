import { DatePipe } from '@angular/common';
import { Component, inject, Input } from '@angular/core';
import { IdlObject } from '@eg/core/idl.service';
import { HoldGroupsService } from '../hold-groups.service';

@Component({
    selector: 'eg-hold-group-info',
    standalone: true,
    imports: [DatePipe],
    templateUrl: './hold-group-info.component.html'
})
export class HoldGroupInfoComponent {
    protected hg = inject(HoldGroupsService);

  @Input() userBucketId?: number;
  @Input() userBucket: IdlObject | null = null;
}
