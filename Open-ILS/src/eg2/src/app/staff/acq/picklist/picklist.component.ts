import {Component, OnInit} from '@angular/core';
import {ActivatedRoute, ParamMap, RouterModule} from '@angular/router';
import { StaffBannerComponent } from '@eg/staff/share/staff-banner.component';
import { PicklistSummaryComponent } from './summary.component';

/**
 * Parent component for all Selection List sub-displays.
 */


@Component({
    templateUrl: 'picklist.component.html',
    imports: [
        PicklistSummaryComponent,
        RouterModule,
        StaffBannerComponent,
    ]
})
export class PicklistComponent implements OnInit {

    picklistId: number;

    constructor(private route: ActivatedRoute) {}

    ngOnInit() {
        this.route.paramMap.subscribe((params: ParamMap) => {
            this.picklistId = +params.get('picklistId');
        });
    }

    isBasePage(): boolean {
        return !this.route.firstChild ||
            this.route.firstChild.snapshot.url.length === 0;
    }
}
