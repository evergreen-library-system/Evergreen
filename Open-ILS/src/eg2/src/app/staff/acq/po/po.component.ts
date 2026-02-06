import {Component, OnInit} from '@angular/core';
import {ActivatedRoute, ParamMap, RouterModule} from '@angular/router';
import {PoService} from './po.service';
import { StaffBannerComponent } from '@eg/staff/share/staff-banner.component';
import { PoSummaryComponent } from './summary.component';
import { PoChargesComponent } from './charges.component';
import { CommonModule } from '@angular/common';

@Component({
    templateUrl: 'po.component.html',
    imports: [
        CommonModule,
        PoChargesComponent,
        PoSummaryComponent,
        RouterModule,
        StaffBannerComponent,
    ]
})
export class PoComponent implements OnInit {

    poId: number;

    constructor(
        private route: ActivatedRoute,
        public  poService: PoService
    ) {}

    ngOnInit() {
        this.route.paramMap.subscribe((params: ParamMap) => {
            this.poId = +params.get('poId');
        });
    }

    isBasePage(): boolean {
        return !this.route.firstChild ||
            this.route.firstChild.snapshot.url.length === 0;
    }
}

