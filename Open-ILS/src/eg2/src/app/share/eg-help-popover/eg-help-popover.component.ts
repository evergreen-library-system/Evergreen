import { Component, OnInit, Input } from '@angular/core';
import {NgbPopover} from '@ng-bootstrap/ng-bootstrap';

@Component({
    selector: 'eg-help-popover',
    templateUrl: './eg-help-popover.component.html',
    styleUrls: ['./eg-help-popover.component.css']
})
export class EgHelpPopoverComponent implements OnInit {

    // The text to display in the popover
    @Input()
    helpText = '';

    // An optional link to include in the popover. If supplied,
    // the entire helpText is wrapped in it
    @Input()
    helpLink = '';

    // placement value passed to ngbPopover that controls
    // where the popover is displayed. Values include
    // 'auto', 'right', 'left', 'top-left', 'bottom-right',
    // 'top', and so forth.
    @Input()
    placement = '';

    constructor() { }

    ngOnInit() {
    }

}
