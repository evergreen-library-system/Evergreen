import { Component, Input } from '@angular/core';

@Component({
    selector: 'eg-help-popover',
    templateUrl: './eg-help-popover.component.html',
    styleUrls: ['./eg-help-popover.component.css']
})
export class EgHelpPopoverComponent {

    // The text to display in the popover
    @Input()
        helpText = '';

    // An optional link to include in the popover. If supplied,
    // the entire helpText is wrapped in it
    @Input()
        helpLink = '';

    // placement value passed to ngbPopover that controls
    // where the popover is displayed. Values include
    // 'auto', 'start', 'end', 'top-start', 'bottom-end',
    // 'top', and so forth.
    @Input()
        placement = 'auto';

    // Allow for overriding the default button class.
    // This augments the basic 'btn' class
    @Input()
        buttonClass = 'btn-sm';
}
