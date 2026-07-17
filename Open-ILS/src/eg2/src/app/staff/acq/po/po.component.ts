import { Component, OnInit, inject } from '@angular/core';
import {ActivatedRoute, ParamMap, RouterModule} from '@angular/router';
import {PoService} from './po.service';
import { StaffBannerComponent } from '@eg/staff/share/staff-banner.component';
import { PoSummaryComponent } from './summary.component';
import { PoChargesComponent } from './charges.component';


@Component({
    templateUrl: 'po.component.html',
    imports: [
        PoChargesComponent,
        PoSummaryComponent,
        RouterModule,
        StaffBannerComponent
    ]
})
export class PoComponent implements OnInit {
    private route = inject(ActivatedRoute);
    poService = inject(PoService);


    poId: number;

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

