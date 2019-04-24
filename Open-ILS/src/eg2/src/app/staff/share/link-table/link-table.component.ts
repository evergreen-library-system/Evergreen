import {Component, Input, OnInit, AfterViewInit, Host} from '@angular/core';

interface LinkTableLink {
    label: string;
    url?: string;
    routerLink?: string;
}

@Component({
    selector: 'eg-link-table',
    templateUrl: './link-table.component.html'
})

export class LinkTableComponent implements AfterViewInit {
    @Input() columnCount: number;
    links: LinkTableLink[];
    rowBuckets: any[];
    colList: number[];
    colWidth: number;

    constructor() {
        this.links = [];
        this.rowBuckets = [];
        this.colList = [];
    }

    ngAfterViewInit() {
        // table-ize the links
        const rowCount = Math.ceil(this.links.length / this.columnCount);
        this.colWidth = Math.floor(12 / this.columnCount); // Bootstrap 12-grid

        for (let col = 0; col < this.columnCount; col++) {
            this.colList.push(col);
        }

        // Modifying values in AfterViewInit without other activity
        // happening can result in the modified values not getting
        // displayed until some action occurs.  Modifing after
        // via timeout works though.
        setTimeout(() => {
            for (let row = 0; row < rowCount; row++) {
                this.rowBuckets[row] = [
                    this.links[row],
                    this.links[row + Number(rowCount)],
                    this.links[row + Number(rowCount * 2)]
                ];
            }
        });
    }
}

@Component({
    selector: 'eg-link-table-link',
    template: '<ng-template></ng-template>'
})

export class LinkTableLinkComponent implements OnInit {
    @Input() label: string;
    @Input() url: string;
    @Input() routerLink: string;

    constructor(@Host() private linkTable: LinkTableComponent) {}

    ngOnInit() {
        this.linkTable.links.push({
            label : this.label,
            url: this.url,
            routerLink: this.routerLink
        });
    }
}


