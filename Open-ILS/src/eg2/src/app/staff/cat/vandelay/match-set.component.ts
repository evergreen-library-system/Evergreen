import { Component, OnInit, inject } from '@angular/core';
import {Router, ActivatedRoute, ParamMap} from '@angular/router';
import {NgbNavChangeEvent} from '@ng-bootstrap/ng-bootstrap';
import {IdlObject} from '@eg/core/idl.service';
import {PcrudService} from '@eg/core/pcrud.service';
import {OrgService} from '@eg/core/org.service';
import { StaffCommonModule } from '@eg/staff/common.module';
import { MatchSetQualityComponent } from './match-set-quality.component';
import { MatchSetExpressionComponent } from './match-set-expression.component';

@Component({
    templateUrl: 'match-set.component.html',
    imports: [StaffCommonModule, MatchSetQualityComponent, MatchSetExpressionComponent]
})
export class MatchSetComponent implements OnInit {
    private router = inject(Router);
    private route = inject(ActivatedRoute);
    private pcrud = inject(PcrudService);
    private org = inject(OrgService);


    matchSet: IdlObject;
    matchSetId: number;
    matchSetTab: string;

    constructor() {
        this.route.paramMap.subscribe((params: ParamMap) => {
            this.matchSetId = +params.get('id');
            this.matchSetTab = params.get('matchSetTab');
        });
    }

    ngOnInit() {
        this.pcrud.retrieve('vms', this.matchSetId)
            .toPromise().then(ms => {
                ms.owner(this.org.get(ms.owner()));
                this.matchSet = ms;
            });
    }

    // Changing a tab in the UI means changing the route.
    // Changing the route ultimately results in changing the tab.
    onNavChange(evt: NgbNavChangeEvent) {
        this.matchSetTab = evt.nextId;

        // prevent tab changing until after route navigation
        evt.preventDefault();

        const url =
          `/staff/cat/vandelay/match_sets/${this.matchSetId}/${this.matchSetTab}`;

        this.router.navigate([url]);
    }
}

