import {Component, Input, OnInit, Host} from '@angular/core';

interface LinkTableLink {
    label: string;
    url?: string;
    routerLink?: string;
}

@Component({
    selector: 'eg-link-table',
    templateUrl: './link-table.component.html',
    styleUrls: ['link-table.component.css'],
    styles: [
        `
      ul {
        column-count: var(--columnCount);
      }
    `
    ]
})

export class LinkTableComponent {
    @Input() columnCount: number;
    links: LinkTableLink[];

    constructor() {
        this.links = [];
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


