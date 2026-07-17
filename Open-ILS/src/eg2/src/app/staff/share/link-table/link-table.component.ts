
import { Component, Input, OnInit, inject } from '@angular/core';
import { RouterModule } from '@angular/router';

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
    ],
    imports: [
        RouterModule
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
    private linkTable = inject(LinkTableComponent, { host: true });

    @Input() label: string;
    @Input() url: string;
    @Input() routerLink: string;

    ngOnInit() {
        this.linkTable.links.push({
            label : this.label,
            url: this.url,
            routerLink: this.routerLink
        });
    }
}


