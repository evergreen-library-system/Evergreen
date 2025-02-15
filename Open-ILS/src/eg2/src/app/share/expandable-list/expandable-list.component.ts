import { Component, ElementRef, Input, ViewChild } from '@angular/core';
import { CommonModule } from '@angular/common';
import { ShowMoreComponent } from '../show-more/show-more.component';
import { Params } from '@angular/router';

export interface ExpandableListEntry {
    text: string,
    routerLink?: string | any[],
    queryParams?: Params,
    displayLink?: boolean
}

const HALF_SECOND = 500;

@Component({
    selector: 'eg-expandable-list',
    standalone: true,
    imports: [CommonModule, ShowMoreComponent],
    templateUrl: './expandable-list.component.html',
    styleUrls: ['./expandable-list.component.css']
})
export class ExpandableListComponent {
    @Input() entries: ExpandableListEntry[];
    @Input() characterLimit: number;
    @Input() entryLimit: number;
    @Input() inline: boolean;
    @ViewChild('list') list!: ElementRef;

    collapsed = true;

    get truncatedEntries(): ExpandableListEntry[] {
        if (this.shouldTruncate) {
            return this.entries?.slice(0, this.entryLimit) || [];
        }
        return this.entries;
    }

    get shouldTruncate(): boolean {
        return this.entryLimit && this.entryLimit < this.entries.length;
    }

    expand(): void {
        this.collapsed = false;
        this.focusList();
    }

    collapse(): void {
        this.collapsed = true;
        this.focusList();
    }

    private focusList(): void {
        // A brief pause for the screen reader's virtual buffer
        // to count the number of items now in the list, then set focus
        // to inform the screen reader user of the new list item count.
        setTimeout(() => {
            this.list.nativeElement.focus({ preventScroll: true });
        }, HALF_SECOND);
    }
}
