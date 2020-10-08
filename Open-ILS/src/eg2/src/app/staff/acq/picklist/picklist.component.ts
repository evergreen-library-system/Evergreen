import {Component, OnInit} from '@angular/core';
import {ActivatedRoute, ParamMap} from '@angular/router';

/**
 * Parent component for all Selection List sub-displays.
 */


@Component({
  templateUrl: 'picklist.component.html'
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
