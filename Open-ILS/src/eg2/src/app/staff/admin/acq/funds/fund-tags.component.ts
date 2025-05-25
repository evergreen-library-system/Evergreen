import {Component, OnInit, Input, ViewChild} from '@angular/core';
import {IdlService, IdlObject} from '@eg/core/idl.service';
import {EventService} from '@eg/core/event.service';
import {NetService} from '@eg/core/net.service';
import {AuthService} from '@eg/core/auth.service';
import {PcrudService} from '@eg/core/pcrud.service';
import {OrgService} from '@eg/core/org.service';
import {StringComponent} from '@eg/share/string/string.component';
import {ToastService} from '@eg/share/toast/toast.service';
import {ComboboxComponent, ComboboxEntry} from '@eg/share/combobox/combobox.component';
import {Observable, map} from 'rxjs';

@Component({
    selector: 'eg-fund-tags',
    templateUrl: './fund-tags.component.html'
})
export class FundTagsComponent implements OnInit {

    @Input() fundId: number;
    @Input() fundOwner: number;

    @ViewChild('addSuccessString', { static: true }) addSuccessString: StringComponent;
    @ViewChild('addErrorString', { static: true }) addErrorString: StringComponent;
    @ViewChild('removeSuccessString', { static: true }) removeSuccessString: StringComponent;
    @ViewChild('removeErrorString', { static: true }) removeErrorString: StringComponent;
    @ViewChild('tagSelector', { static: false }) tagSelector: ComboboxComponent;

    tagMaps: IdlObject[];
    newTag: ComboboxEntry = null;
    tagSelectorDataSource: (term: string) => Observable<ComboboxEntry>;

    constructor(
        private idl: IdlService,
        private evt: EventService,
        private net: NetService,
        private auth: AuthService,
        private pcrud: PcrudService,
        private org: OrgService,
        private toast: ToastService
    ) {}

    ngOnInit() {
        this._loadTagMaps();
        this.tagSelectorDataSource = term => {
            const field = 'name';
            const args = {};
            const extra_args = { order_by : {} };
            args[field] = {'ilike': `%${term}%`}; // could -or search on label
            args['owner'] = this.org.ancestors(this.fundOwner, true);
            extra_args['order_by']['acqft'] = field;
            extra_args['limit'] = 100;
            extra_args['flesh'] = 2;
            const flesh_fields: Object = {};
            flesh_fields['acqft'] = ['owner'];
            extra_args['flesh_fields'] = flesh_fields;
            return this.pcrud.search('acqft', args, extra_args).pipe(map(data => {
                return {
                    id: data.id(),
                    label: data.name() + ' (' + data.owner().shortname() + ')',
                    fm: data
                };
            }));
        };
    }

    _loadTagMaps() {
        this.tagMaps = [];
        this.pcrud.search('acqftm', { fund: this.fundId }, {
            flesh: 2,
            flesh_fields: {
                acqftm: ['tag'],
                acqft:  ['owner']
            }
        }).subscribe(
            { next: res => this.tagMaps.push(res), error: (err: unknown) => {}, complete: () => this.tagMaps.sort((a, b) => {
                return a.tag().name() < b.tag().name() ? -1 : 1;
            }) }
        );
    }

    checkNewTagAlreadyMapped(): boolean {
        // eslint-disable-next-line eqeqeq
        if ( this.newTag == null) { return false; }
        const matches: IdlObject[] = this.tagMaps.filter(tm => tm.tag().id() === this.newTag.id);
        return matches.length > 0 ? true : false;
    }

    addTagMap() {
        const ftm = this.idl.create('acqftm');
        ftm.tag(this.newTag.id);
        ftm.fund(this.fundId);
        this.pcrud.create(ftm).subscribe(
            { next: ok => {
                this.addSuccessString.current()
                    .then(str => this.toast.success(str));
            }, error: (err: unknown) => {
                this.addErrorString.current()
                    .then(str => this.toast.danger(str));
            }, complete: () => {
                this.newTag = null;
                this.tagSelector.selectedId = null;
                this._loadTagMaps();
            } }
        );
    }
    removeTagMap(ftm: IdlObject) {
        this.pcrud.remove(ftm).subscribe(
            { next: ok => {
                this.removeSuccessString.current()
                    .then(str => this.toast.success(str));
            }, error: (err: unknown) => {
                this.removeErrorString.current()
                    .then(str => this.toast.danger(str));
            }, complete: () => this._loadTagMaps() }
        );
    }
}
