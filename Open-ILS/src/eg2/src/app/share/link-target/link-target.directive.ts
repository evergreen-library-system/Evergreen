import { Directive, ElementRef, HostBinding } from '@angular/core';
import { LinkTargetService } from './link-target.service';
import { take } from 'rxjs';

/**
 * <a target="_blank">...</a>
 *
 * - removes target attribute from links that open in a new tab
 *   if the setting ui.staff.disable_links_newtabs is true
 *
 * - adds aria-describedby="link-opens-newtab" to links that
 *   open in a new tab if ui.staff.disable_links_newtabs is false
 */

const NEW_TAB_DESCRIBER_ID = 'link-opens-newtab';
const SAME_TAB_TARGETS = new Set(['_self', '_parent', '_top']);

@Directive({
    // eslint-disable-next-line @angular-eslint/directive-selector
    selector: 'a[target]'
})
export class LinkTargetDirective {

    private newTabsDisabled?: boolean;

    @HostBinding('attr.target')
    get target(): string | null {
        const target = this.el.nativeElement.getAttribute('target');
        return this.newTabsDisabled && !SAME_TAB_TARGETS.has(target)
            ? null
            : target;
    }

    @HostBinding('attr.aria-describedby')
    get describedBy(): string | null {
        const el = this.el.nativeElement;
        const target = el.getAttribute('target');
        const describedBy = el.getAttribute('aria-describedby');

        let ids: string[] = [];
        if (describedBy) {
            ids = describedBy
                .split(/\s+/)
                .filter(id => id !== NEW_TAB_DESCRIBER_ID);
        }

        if (!this.newTabsDisabled && !SAME_TAB_TARGETS.has(target)) {
            ids.push(NEW_TAB_DESCRIBER_ID);
        }

        return ids.length ? ids.join(' ') : null;
    }

    constructor(
        private readonly el: ElementRef<HTMLAnchorElement>,
        private readonly linkTarget: LinkTargetService
    ) {
        // the UI for the workstation setting is in AngularJS,
        // so we won't get more than one emission here
        this.linkTarget.newTabsDisabled$.pipe(
            take(1),
        ).subscribe(disabled => {
            this.newTabsDisabled = disabled;
        });
    }
}
