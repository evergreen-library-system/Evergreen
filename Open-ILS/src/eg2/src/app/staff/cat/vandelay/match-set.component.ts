import {Component, OnInit, ViewChild} from '@angular/core';
import {Router, ActivatedRoute, ParamMap} from '@angular/router';
import {NgbTabset, NgbTabChangeEvent} from '@ng-bootstrap/ng-bootstrap';
import {IdlObject} from '@eg/core/idl.service';
import {PcrudService} from '@eg/core/pcrud.service';
import {OrgService} from '@eg/core/org.service';

@Component({
  templateUrl: 'match-set.component.html'
})
export class MatchSetComponent implements OnInit {

    matchSet: IdlObject;
    matchSetId: number;
    matchSetTab: string;

    constructor(
        private router: Router,
        private route: ActivatedRoute,
        private pcrud: PcrudService,
        private org: OrgService
    ) {
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
    onTabChange(evt: NgbTabChangeEvent) {
        this.matchSetTab = evt.nextId;

        // prevent tab changing until after route navigation
        evt.preventDefault();

        const url =
          `/staff/cat/vandelay/match_sets/${this.matchSetId}/${this.matchSetTab}`;

        this.router.navigate([url]);
    }
}

