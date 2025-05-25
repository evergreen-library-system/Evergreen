import {Component, OnInit, Input, ViewChild} from '@angular/core';
import {ActivatedRoute} from '@angular/router';
import {PcrudService} from '@eg/core/pcrud.service';
import {StringComponent} from '@eg/share/string/string.component';
import {ToastService} from '@eg/share/toast/toast.service';
import {OrgService} from '@eg/core/org.service';
import {ComboboxEntry} from '@eg/share/combobox/combobox.component';
import {IdlService } from '@eg/core/idl.service';
import {NgbNav, NgbNavChangeEvent} from '@ng-bootstrap/ng-bootstrap';

@Component({
    templateUrl: './circ_limit_set_edit.component.html'
})

export class CircLimitSetEditComponent  implements OnInit {
    recordId: number;
    recordName: String;
    locations: any[];
    circMods: any[];
    allCircMods: any[];
    limitGroups: any[];
    allLimitGroups: any[];
    selectedCircMod: any;
    selectedLocation: any;
    selectedLimitGroup: any;
    locId = 0;

    circTab: 'limitSet' | 'linked' = 'linked';

    @ViewChild('addingSuccess', {static: true}) addingSuccess: StringComponent;
    @ViewChild('removingSuccess', {static: true}) removingSuccess: StringComponent;
    @ViewChild('savingEntryError', {static: true}) savingEntryError: StringComponent;
    @ViewChild('deletingEntryError', {static: true}) deletingEntryError: StringComponent;
    @ViewChild('updatingEntryError', {static: true}) updatingEntryError: StringComponent;
    @ViewChild('savedSuccess', {static: true}) savedSuccess: StringComponent;

    constructor(
        private org: OrgService,
        private route: ActivatedRoute,
        private pcrud: PcrudService,
        private toast: ToastService,
        private idl: IdlService,
    ) {
        this.locations = [];
        this.circMods = [];
        this.allCircMods = [];
        this.limitGroups = [];
        this.allLimitGroups = [];
    }

    ngOnInit() {
        this.recordId = parseInt(this.route.snapshot.paramMap.get('id'), 10);

        // get current circ limit set name to display on the banner
        this.pcrud.search('ccls',
            {id: this.recordId}, {}).toPromise().then(rec => {
            this.recordName = rec.name();
        });

        this.pcrud.search('cclscmm', {limit_set: this.recordId},
            {
                flesh: 1,
                flesh_fields: {cclscmm: ['circ_mod', 'name', 'code']},
                order_by: {}
            }).subscribe(data => {
            data.deleted = false;
            data.name = data.circ_mod().name();
            data.code = data.circ_mod().code();
            this.circMods.push(data);
        });

        this.pcrud.retrieveAll('ccm', { order_by: {} },
            {fleshSelectors: true}).subscribe(data => {
            this.allCircMods.push(data);
        });

        this.pcrud.retrieveAll('cclg', { order_by: {} },
            {fleshSelectors: true}).subscribe(data => {
            this.allLimitGroups.push(data);
        });

        this.pcrud.search('cclsacpl', {limit_set: this.recordId},
            {
                flesh: 1,
                flesh_fields: {cclsacpl: ['copy_loc', 'name']},
                order_by: {}
            }).subscribe(location => {
            location.deleted = false;
            location.shortname = this.org.get(location.copy_loc().owning_lib()).shortname();
            location.name = location.copy_loc().name();
            this.locations.push(location);
        });

        this.pcrud.search('cclsgm', {limit_set: this.recordId},
            {
                flesh: 1,
                flesh_fields: {cclsgm: ['limit_group', 'check_only']},
                order_by: {}
            }).subscribe(data => {
            const checked = data.check_only();
            data.checked = (checked === 't');
            data.checkedOriginalValue = (checked === 't');
            data.name = data.limit_group().name();
            data.deleted = false;
            this.limitGroups.push(data);
        });
    }

    onTabChange(event: NgbNavChangeEvent) {
        this.circTab = event.nextId;
    }

    addLocation() {
        if (!this.selectedLocation) { return; }
        const newCircModMap = this.idl.create('cclsacpl');
        newCircModMap.copy_loc(this.selectedLocation);
        newCircModMap.limit_set(this.recordId);
        newCircModMap.shortname =
            this.org.get(this.selectedLocation.owning_lib()).shortname();
        newCircModMap.name = this.selectedLocation.name();
        newCircModMap.new = true;
        newCircModMap.deleted = false;
        this.locations.push(newCircModMap);
        this.addingSuccess.current().then(msg => this.toast.success(msg));
    }

    addCircMod() {
        if (!this.selectedCircMod) { return; }
        const newName = this.selectedCircMod.name;
        const newCode = this.selectedCircMod.code;
        const newCircModMap = this.idl.create('cclscmm');
        newCircModMap.limit_set(this.recordId);
        newCircModMap.name = newName;
        newCircModMap.code = newCode;
        newCircModMap.new = true;
        newCircModMap.deleted = false;
        let newCircMod: any;
        this.allCircMods.forEach(c => {
            if ((c.name() === newName) && (c.code() === newCode)) {
                newCircMod = this.idl.clone(c);
            }
        });
        newCircModMap.circ_mod(newCircMod);
        this.circMods.push(newCircModMap);
        this.addingSuccess.current().then(msg => this.toast.success(msg));
    }

    circModChanged(entry: ComboboxEntry) {
        if (entry) {
            this.selectedCircMod = {
                code: entry.id,
                name: entry.label
            };
        } else {
            this.selectedCircMod = null;
        }
    }

    removeLocation(location) {
        const id = location.copy_loc().id();
        if (location.new) {
            this.locations.forEach((loc, index) => {
                if (loc.copy_loc().id() === id) {
                    this.locations.splice(index, 1);
                }
            });
        }
        location.deleted = true;
        this.removingSuccess.current().then(msg => this.toast.success(msg));
    }

    removeEntry(entry, array) {
        // if we haven't saved yet, then remove this entry from local array
        if (entry.new) {
            const name = entry.name;
            array.forEach((item, index) => {
                if (item.name === name) {
                    array.splice(index, 1);
                }
            });
        }
        entry.deleted = true;
        this.removingSuccess.current().then(msg => this.toast.success(msg));
    }

    addLimitGroup() {
        if (!this.selectedLimitGroup) { return; }
        const newName = this.selectedLimitGroup.name;
        let undeleting = false;
        this.limitGroups.forEach(group => {
            if (newName === group.name) {
                if (group.deleted === true) {
                    group.deleted = false;
                    undeleting = true;
                    this.addingSuccess.current().then(msg => this.toast.success(msg));
                }
            }
        });
        if (undeleting) { return; }
        const newLimitGroupMap = this.idl.create('cclsgm');
        newLimitGroupMap.limit_set(this.recordId);
        newLimitGroupMap.name = newName;
        newLimitGroupMap.new = true;
        newLimitGroupMap.checked = false;
        newLimitGroupMap.check_only(false);
        newLimitGroupMap.deleted = false;
        let newLimitGroup: any;
        this.allLimitGroups.forEach(c => {
            if (c.name() === newName) {
                newLimitGroup = this.idl.clone(c);
            }
        });
        newLimitGroupMap.limit_group(newLimitGroup);
        this.limitGroups.push(newLimitGroupMap);
        this.addingSuccess.current().then(msg => this.toast.success(msg));
    }

    limitGroupChanged(entry: ComboboxEntry) {
        if (entry) {
            this.selectedLimitGroup = {
                name: entry.label,
                checked: false
            };
        } else {
            this.selectedLimitGroup = null;
        }
    }

    save() {
        const allData = [this.circMods, this.locations, this.limitGroups];
        let errorOccurred = false;
        allData.forEach( array => {
            array.forEach((item) => {
                if (item.new) {
                    if (array === this.limitGroups) {
                        item.check_only(item.checked);
                    }
                    this.pcrud.create(item).subscribe(
                        { next: ok => {
                            const id = ok.id();
                            item.id(id);
                            item.new = false;
                            if (array === this.limitGroups) {
                                item.checkedOriginalValue = item.checked;
                            }
                        }, error: (err: unknown) => {
                            errorOccurred = true;
                            this.savingEntryError.current().then(msg =>
                                this.toast.warning(msg));
                        } }
                    );
                // only delete this from db if we haven't deleted it before
                } else if ((item.deleted) && (!item.deletedSuccess)) {
                    this.pcrud.remove(item).subscribe(
                        { next: ok => {
                            item.deletedSuccess = true;
                        }, error: (err: unknown) => {
                            errorOccurred = true;
                            this.deletingEntryError.current().then(msg =>
                                this.toast.warning(msg));
                        } }
                    );
                // check limit group items to see if the checkbox changed since last write
                } else if ((array === this.limitGroups) && (!item.deleted) &&
                    (!item.new) && (item.checked !== item.checkedOriginalValue)) {
                    item.check_only(item.checked);
                    this.pcrud.update(item).subscribe(
                        { next: ok => {
                            item.checkedOriginalValue = item.checked;
                        }, error: (err: unknown) => {
                            errorOccurred = true;
                            this.updatingEntryError.current().then(msg =>
                                this.toast.warning(msg));
                        } }
                    );
                }
            });
        });

        if (!errorOccurred) {
            this.savedSuccess.current().then(msg => this.toast.success(msg));
        }
    }
}
