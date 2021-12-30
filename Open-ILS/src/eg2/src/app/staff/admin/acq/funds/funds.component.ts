import {Component, OnInit, Input, ViewChild} from '@angular/core';
import {Router, ActivatedRoute, ParamMap} from '@angular/router';
import {Location} from '@angular/common';
import {NgbNav, NgbNavChangeEvent} from '@ng-bootstrap/ng-bootstrap';

@Component({
    templateUrl: './funds.component.html'
})
export class FundsComponent implements OnInit {

    activeTab: string;
    fundId: number;
    fundingSourceId: number;

    constructor(
        private location: Location,
        private router: Router,
        private route: ActivatedRoute
    ) {}

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
