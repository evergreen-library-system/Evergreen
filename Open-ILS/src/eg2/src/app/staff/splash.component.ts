import {Component, OnInit, AfterViewInit, Directive, ElementRef, Renderer2, ViewChild} from '@angular/core';
import {OrgService} from '@eg/core/org.service';
import {AuthService} from '@eg/core/auth.service';
import {PcrudService} from '@eg/core/pcrud.service';
import {ToastService} from '@eg/share/toast/toast.service';
import {StringComponent} from '@eg/share/string/string.component';
import {Router} from '@angular/router';

@Component({
    templateUrl: 'splash.component.html',
    styleUrls: ['./splash.component.css']
})

export class StaffSplashComponent implements OnInit {

    @ViewChild('noPermissionString', { static: true }) noPermissionString: StringComponent;
    catSearchQuery: string;
    portalEntries: any[][] = [];
    portalHeaders: any[] = [];

    constructor(
        private renderer: Renderer2,
        private pcrud: PcrudService,
        private auth: AuthService,
        private org: OrgService,
        private router: Router,
        private toast: ToastService
    ) {}

    ngOnInit() {
        const tmpPortalEntries: any[][] = [];
        const wsAncestors = this.org.ancestors(this.auth.user().ws_ou(), true);
        this.pcrud.search('cusppe', {owner: wsAncestors}).subscribe(
            item => {
                const page_col = item.page_col();
                if (tmpPortalEntries[page_col] === undefined) {
                    tmpPortalEntries[page_col] = [];
                }
                if (tmpPortalEntries[page_col][item.col_pos()] === undefined) {
                    tmpPortalEntries[page_col][item.col_pos()] = [];
                }
                // we push here, then flatten the results when we filter
                // by owner later because (page_col, col_pos) is not
                // guaranteed to be unique
                tmpPortalEntries[page_col][item.col_pos()].push(item);
            },
            (err: unknown) => {},
            () => {
                // find the first set of entries belonging to the
                // workstation OU or one of its ancestors
                let filteredPortalEntries: any[][] = [];
                let foundMatch = false;
                for (const ou of wsAncestors) {
                    tmpPortalEntries.forEach((col) => {
                        if (col !== undefined) {
                            const filtered = col.reduce((prev, curr) => prev.concat(curr), [])
                                .filter(x => x !== undefined)
                                .filter(x => ou === x.owner());
                            if (filtered.length) {
                                foundMatch = true;
                                filteredPortalEntries.push(filtered);
                            }
                        }
                    });
                    if (foundMatch) {
                        break;
                    } else {
                        filteredPortalEntries = [];
                    }
                }

                // munge the results so that we don't need to
                // care if there are gaps in the page_col or col_pos
                // sequences
                filteredPortalEntries.forEach((col) => {
                    if (col !== undefined) {
                        const filtered = col.filter(x => x !== undefined);
                        this.portalEntries.push(filtered);
                        filtered.forEach((entry) => {
                            if (entry.entry_type() === 'header') {
                                this.portalHeaders[this.portalEntries.length - 1] = entry;
                            }
                        });
                    }
                });
                // supply an empty header entry in case a column was
                // defined without a header
                this.portalEntries.forEach((col, i) => {
                    if (this.portalHeaders.length <= i) {
                        this.portalHeaders[i] = undefined;
                    }
                });
            }
        );

        if (this.router.url === '/staff/no_permission') {
            this.noPermissionString.current()
                .then(str => {
                    this.toast.danger(str);
                    this.router.navigate(['/staff']);
                });
        }
    }

    searchCatalog(): void {
        if (!this.catSearchQuery) { return; }

        this.router.navigate(
            ['/staff/catalog/search'],
            {queryParams: {query : this.catSearchQuery}}
        );
    }
}

@Directive({
    selector: '[egAutofocus]'
})
export class AutofocusDirective implements AfterViewInit {
    constructor(private host: ElementRef) {}

    ngAfterViewInit() {
        this.host.nativeElement.focus();
    }
}
