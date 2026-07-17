import { Component, OnInit, inject } from '@angular/core';
import {Router, ActivatedRoute, ParamMap} from '@angular/router';
import {Location} from '@angular/common';
import {NgbNavChangeEvent} from '@ng-bootstrap/ng-bootstrap';
import { StaffCommonModule } from '@eg/staff/common.module';
import { FundsManagerComponent } from './funds-manager.component';
import { FundingSourcesComponent } from './funding-sources.component';
import { AdminPageComponent } from '@eg/staff/share/admin-page/admin-page.component';

@Component({
    templateUrl: './funds.component.html',
    imports: [
        AdminPageComponent,
        FundingSourcesComponent,
        FundsManagerComponent,
        StaffCommonModule,
    ]
})
export class FundsComponent implements OnInit {
    private location = inject(Location);
    private router = inject(Router);
    private route = inject(ActivatedRoute);


    activeTab: string;
    fundId: number;
    fundingSourceId: number;

    ngOnInit() {
        this.route.paramMap.subscribe((params: ParamMap) => {
            const tab = params.get('tab');
            const id = +params.get('id');
            if (!id || !tab) { return; }
            if (tab === 'fund' || tab === 'funding_source') {
                this.activeTab = tab;
                if (tab === 'fund') {
                    this.fundId = id;
                } else {
                    this.fundingSourceId = id;
                }
            } else {
                return;
            }
        });
    }

    // Changing a tab in the UI means clearing the route (e.g.,
    // if we originally navigated vi funds/fund/:id or
    // funds/funding_source/:id
    onNavChange(evt: NgbNavChangeEvent) {
        // clear any IDs parsed from the original route
        // to avoid reopening the fund or funding source
        // dialogs when navigating back to the fund/funding source
        // tab.
        this.fundId = null;
        this.fundingSourceId = null;
        const url = this.router.createUrlTree(['/staff/admin/acq/funds']).toString();
        this.location.go(url); // go without reloading
    }
}
