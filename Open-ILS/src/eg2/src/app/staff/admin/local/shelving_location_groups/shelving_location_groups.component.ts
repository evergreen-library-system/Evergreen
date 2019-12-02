import {Component, OnInit, Input, ViewChild} from '@angular/core';
import {IdlService, IdlObject} from '@eg/core/idl.service';
import {OrgService} from '@eg/core/org.service';
import {PcrudService} from '@eg/core/pcrud.service';
import {FmRecordEditorComponent} from '@eg/share/fm-editor/fm-editor.component';
import {StringComponent} from '@eg/share/string/string.component';
import {ToastService} from '@eg/share/toast/toast.service';
import {PermService} from '@eg/core/perm.service';

@Component({
    templateUrl: './shelving_location_groups.component.html'
})

export class ShelvingLocationGroupsComponent implements OnInit {

    selectedOrg: IdlObject;
    selectedOrgId = 1;
    locationGroups: IdlObject[];
    shelvingLocations: IdlObject[];
    groupEntries: IdlObject[];
    selectedLocationGroupId: number;
    selectedLocationGroup: IdlObject;
    permissions: number[];
    hasPermission = false;
    draggedElement: IdlObject;
    dragTarget: IdlObject;
    defaultNewRecord: IdlObject;

    @ViewChild ('editDialog', { static: true }) private editDialog: FmRecordEditorComponent;
    @ViewChild ('editLocGroupSuccess', {static: true}) editLocGroupSuccess: StringComponent;
    @ViewChild ('editLocGroupFailure', {static: true}) editLocGroupFailure: StringComponent;
    @ViewChild ('addedGroupEntriesSuccess', {static: true})
        addedGroupEntriesSuccess: StringComponent;
    @ViewChild ('addedGroupEntriesFailure', {static: true})
        addedGroupEntriesFailure: StringComponent;
    @ViewChild ('removedGroupEntriesSuccess', {static: true})
        removedGroupEntriesSuccess: StringComponent;
    @ViewChild ('removedGroupEntriesFailure', {static: true})
        removedGroupEntriesFailure: StringComponent;
    @ViewChild ('changeOrderSuccess', {static: true}) changeOrderSuccess: StringComponent;
    @ViewChild ('changeOrderFailure', {static: true}) changeOrderFailure: StringComponent;

    constructor(
        private org: OrgService,
        private pcrud: PcrudService,
        private toast: ToastService,
        private idl: IdlService,
        private perm: PermService
    ) {
       this.permissions = [];
    }

    ngOnInit() {
        this.loadLocationGroups();
        this.perm.hasWorkPermAt(['ADMIN_COPY_LOCATION_GROUP'], true).then((perm) => {
            this.permissions = perm['ADMIN_COPY_LOCATION_GROUP'];
            this.checkCurrentPermissions();
        });
    }

    checkCurrentPermissions = () => {
        this.hasPermission =
            (this.permissions.indexOf(this.selectedOrgId) !== -1);
    }

    createLocationGroup = () => {
        this.editDialog.mode = 'create';
        this.defaultNewRecord = this.idl.create('acplg');
        this.defaultNewRecord.owner(this.selectedOrgId);
        let highestPosition = 0;
        if (this.locationGroups.length) {
            highestPosition = this.locationGroups[0].posit;
            this.locationGroups.forEach(grp => {
                if (grp.posit > highestPosition) {
                    highestPosition = grp.posit;
                }
            });
        }
        // make the new record the last one on the list
        this.defaultNewRecord.pos(highestPosition + 1);
        this.editDialog.record = this.defaultNewRecord;
        this.editDialog.recordId = null;
        this.editDialog.open({size: 'lg'}).subscribe(
            newLocationGroup => {
                this.processLocationGroup(newLocationGroup);
                this.locationGroups.push(newLocationGroup);
                // select it by default if it's the only location group
                if (this.locationGroups.length === 1) {
                    this.markAsSelected(newLocationGroup);
                } else {
                    this.sortLocationGroups();
                }
                console.debug('Record editor performed action');
            }, err => {
                console.debug(err);
            }
        );
    }

    processLocationGroup = (locationGroup) => {
        locationGroup.isVisible = (locationGroup.opac_visible() === 't');
        locationGroup.posit = locationGroup.pos();
        locationGroup.name = locationGroup.name();
    }

    editLocationGroup = (group) => {
        this.editDialog.mode = 'update';
        this.editDialog.recordId = group.id();
        this.editDialog.open({size: 'lg'}).subscribe(
            id => {
                console.debug('Record editor performed action');
                this.loadLocationGroups();
            },
            err => {
                console.debug(err);
            },
            () => console.debug('Dialog closed')
        );
    }

    deleteLocationGroup = (locationGroupToDelete) => {
        const idToDelete = locationGroupToDelete.id();
        this.pcrud.remove(locationGroupToDelete).subscribe(
            ok => {
                this.locationGroups.forEach((locationGroup, index) => {
                    if (locationGroup.id() === idToDelete) {
                        this.locationGroups.splice(index, 1);
                    }
                });
            },
            err => console.debug(err)
        );
    }

    sortLocationGroups = () => {
        this.locationGroups.sort((a, b) => (a.posit > b.posit) ? 1 : -1);
    }

    loadLocationGroups = () => {
        this.locationGroups = [];
        this.pcrud.search('acplg', {owner: this.selectedOrgId}, {
            flesh: 1,
            flesh_fields: {acplg: ['opac_visible', 'pos', 'name']},
            order_by: {acplg: 'owner'}
        }).subscribe(data => {
            this.processLocationGroup(data);
            this.locationGroups.push(data);
        }, (error) => {
            console.debug(error);
        }, () => {
            this.sortLocationGroups();
            if (this.locationGroups.length) {
                this.markAsSelected(this.locationGroups[0]);
            }
            this.loadGroupEntries();
        });
    }

    changeSelectedLocationGroup = (group) => {
        this.selectedLocationGroup.selected = false;
        this.markAsSelected(group);
        this.loadGroupEntries();
    }

    markAsSelected = (locationGroup) => {
        this.selectedLocationGroup = locationGroup;
        this.selectedLocationGroup.selected = true;
        this.selectedLocationGroupId = locationGroup.id();
    }

    loadGroupEntries = () => {
        this.groupEntries = [];
        this.pcrud.search('acplgm', {lgroup: this.selectedLocationGroupId}, {
            flesh: 1,
            flesh_fields: {acplgm: ['location']},
            order_by: {acplgm: ['location']}
        }).subscribe(data => {
            data.name = data.location().name();
            data.shortname = this.org.get(data.location().owning_lib()).shortname();
            // remove all non-alphanumeric chars to make label a valid id
            data.label = (data.shortname + data.name).replace(/\W/g, '');
            data.checked = false;
            this.groupEntries.push(data);
        }, (error) => {
            console.debug(error);
        }, () => {
            this.loadShelvingLocations();
        });
    }

    loadShelvingLocations = () => {
        let orgList = this.org.fullPath(this.selectedOrgId, false);
        orgList.sort(function(a, b) {
            return a.ou_type().depth() < b.ou_type().depth() ? -1 : 1;
        });
        orgList = orgList.map((member) => {
            return member.id();
        });
        const groupEntryIds = this.groupEntries.map(
            (group) => group.location().id());
        this.shelvingLocations = [];
        this.pcrud.search('acpl', {owning_lib : orgList, deleted: 'f'})
        .subscribe(data => {
            data.name = data.name();
            data.shortname = this.org.get(data.owning_lib()).shortname();
            // remove all non-alphanumeric chars to make label a valid id
            data.label = (data.shortname + data.name).replace(/\W/g, '');
            data.checked = false;
            if (groupEntryIds.indexOf(data.id()) === -1) {
                data.hidden = false;
            } else {
                data.hidden = true;
            }
            this.shelvingLocations.push(data);
        }, (error) => {
            console.debug(error);
        }, () => {
            this.shelvingLocations.sort(function(a, b) {
                return a.name < b.name ? -1 : 1;
            });
            const sortedShelvingLocations = [];
            // order our array primarily by location
            orgList.forEach(member => {
                const currentLocationArray = this.shelvingLocations.filter((loc) => {
                    return (member === loc.owning_lib());
                });
                Array.prototype.push.apply(sortedShelvingLocations, currentLocationArray);
            });
            this.shelvingLocations = sortedShelvingLocations;
        });
    }

    addEntries = () => {
        const checkedEntries = this.shelvingLocations.filter((entry) => {
            return entry.checked;
        });
        checkedEntries.forEach((entry) => {
            const newGroupEntry = this.idl.create('acplgm');
            newGroupEntry.location(entry);
            newGroupEntry.lgroup(this.selectedLocationGroup.id());
            this.pcrud.create(newGroupEntry).subscribe(
                newEntry => {
                    // hide item so it won't show on on list of shelving locations
                    entry.hidden = true;
                    entry.checked = false;
                    newEntry.checked = false;
                    newEntry.location(entry);
                    newEntry.name = entry.name;
                    newEntry.shortname = entry.shortname;
                    this.groupEntries.push(newEntry);
                    this.addedGroupEntriesSuccess.current().then(msg =>
                        this.toast.success(msg));
                },
                err => {
                    console.debug(err);
                    this.addedGroupEntriesFailure.current().then(msg => this.toast.warning(msg));
                }
            );
        });
    }

    removeEntries = () => {
        const checkedEntries = this.groupEntries.filter((entry) => {
            return entry.checked;
        });
        this.pcrud.remove(checkedEntries).subscribe(
            idRemoved => {
                idRemoved = parseInt(idRemoved, 10);
                let deletedName;
                let deletedShortName;
                // on pcrud success, remove from local group entries array
                this.groupEntries = this.groupEntries.filter((entry) => {
                    if (entry.id() === idRemoved) {
                        deletedName = entry.name;
                        deletedShortName = entry.shortname;
                    }
                    return (entry.id() !== idRemoved);
                });
                // show the entry on list of shelving locations
                this.shelvingLocations.forEach((location) => {
                    if ((location.name === deletedName) && (location.shortname ===
                        deletedShortName)) {
                        location.hidden = false;
                    }
                });
                this.removedGroupEntriesSuccess.current().then(msg =>
                    this.toast.success(msg));
            }, (error) => {
                console.debug(error);
                this.removedGroupEntriesFailure.current().then(msg =>
                    this.toast.warning(msg));
            }
        );
    }

    orgOnChange = (org: IdlObject): void => {
        this.selectedOrg = org;
        this.selectedOrgId = org.id();
        this.loadLocationGroups();
        this.checkCurrentPermissions();
    }

    onDragStart = (event, locationGroup) => {
        this.draggedElement = locationGroup;
    }

    onDragOver = (event) => {
        event.preventDefault();
    }

    onDragEnter = (event, locationGroup) => {
        this.dragTarget = locationGroup;
        // remove border where we previously were dragging
        if (event.relatedTarget) {
            event.relatedTarget.parentElement.style.borderTop = 'none';
        }
        // add border above target location group
        if (event.target.parentElement !== null) {
            if (event.target.parentElement.classList.contains('locationGroup')) {
                event.target.parentElement.style.borderTop = '1px solid black';
            }
        }
    }

    onDragDrop = (event, index) => {
        // do nothing if element is dragged onto itself
        if (this.draggedElement !== this.dragTarget) {
            this.assignNewPositions(index);
        }
        event.target.parentElement.style.borderTop = 'none';
        this.draggedElement = null;
        this.dragTarget = null;
    }

    assignNewPositions (index) {
        const endingPos = this.dragTarget.posit;
        const locationGroupsToUpdate = [];
        this.draggedElement.pos(endingPos);
        this.draggedElement.posit = endingPos;
        locationGroupsToUpdate.push(this.draggedElement);
        // add 1 to the position of all groups after the one we inserted
        for (let i = index; i < this.locationGroups.length; i++) {
            // we already processed the item being dragged; skip it
            if (this.locationGroups[i] === this.draggedElement) { continue; }
            const newPosition = this.locationGroups[i].posit + 1;
            this.locationGroups[i].pos(newPosition);
            this.locationGroups[i].posit = newPosition;
            locationGroupsToUpdate.push(this.locationGroups[i]);
        }
        this.saveNewPositions(locationGroupsToUpdate);
    }

    saveNewPositions (locationGroupsToUpdate) {
        let errorHappened = false;
        this.pcrud.update(locationGroupsToUpdate).subscribe(
            ok => {
                console.debug('Record editor performed action');
            },
            err => {
                console.debug(err);
                errorHappened = true;
            },
            () => {
                this.sortLocationGroups();
                if (errorHappened) {
                    this.changeOrderFailure.current().then(msg =>
                        this.toast.warning(msg));
                } else {
                    this.changeOrderSuccess.current().then(msg =>
                        this.toast.success(msg));
                }
            }
        );
    }
}
