import {Component, OnInit, Input, ViewChild} from '@angular/core';
import {finalize} from 'rxjs/operators';
import {IdlService, IdlObject} from '@eg/core/idl.service';
import {OrgService} from '@eg/core/org.service';
import {PcrudService} from '@eg/core/pcrud.service';
import {FmRecordEditorComponent} from '@eg/share/fm-editor/fm-editor.component';
import {StringComponent} from '@eg/share/string/string.component';
import {ToastService} from '@eg/share/toast/toast.service';
import {PermService} from '@eg/core/perm.service';

@Component({
    templateUrl: './shelving_location_groups.component.html',
    styleUrls: ['./shelving_location_groups.component.css']
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
    _loadingShelvingLocations = false;
    _loadingGroupEntries = false;
    _loadingLocationGroups = false;
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
    };

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
            }, (err: unknown) => {
                console.debug(err);
            }
        );
    };

    processLocationGroup = (locationGroup) => {
        locationGroup.isVisible = (locationGroup.opac_visible() === 't');
        locationGroup.posit = locationGroup.pos();
        locationGroup.name = locationGroup.name();
    };

    editLocationGroup = (group) => {
        this.editDialog.mode = 'update';
        this.editDialog.recordId = group.id();
        this.editDialog.open({size: 'lg'}).subscribe(
            id => {
                console.debug('Record editor performed action');
                this.loadLocationGroups();
            },
            (err: unknown) => {
                console.debug(err);
            },
            () => console.debug('Dialog closed')
        );
    };

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
            (err: unknown) => console.debug(err)
        );
    };

    sortLocationGroups = () => {
        this.locationGroups.sort((a, b) => (a.posit > b.posit) ? 1 : -1);
    };

    loadLocationGroups = () => {
        if (this._loadingLocationGroups) {return;}
        this._loadingLocationGroups = true;
        this.locationGroups = [];
        this.pcrud.search('acplg', {owner: this.selectedOrgId}, {
            flesh: 1,
            flesh_fields: {acplg: ['opac_visible', 'pos', 'name']},
            order_by: {acplg: 'owner'}
        }).pipe(finalize(() => this._loadingLocationGroups = false))
            .subscribe(data => {
                this.processLocationGroup(data);
                this.locationGroups.push(data);
            }, (error: unknown) => {
                console.debug(error);
            }, () => {
                this.sortLocationGroups();
                if (this.locationGroups.length) {
                    this.markAsSelected(this.locationGroups[0]);
                }
                this.loadGroupEntries();
            });
    };

    changeSelectedLocationGroup = (group) => {
        this.selectedLocationGroup.selected = false;
        this.markAsSelected(group);
        this.loadGroupEntries();
    };

    markAsSelected = (locationGroup) => {
        this.selectedLocationGroup = locationGroup;
        this.selectedLocationGroup.selected = true;
        this.selectedLocationGroupId = locationGroup.id();
    };

    loadGroupEntries = () => {
        if (this._loadingGroupEntries) {return;}
        this._loadingGroupEntries = true;
        this.groupEntries = [];
        this.pcrud.search('acplgm', {lgroup: this.selectedLocationGroupId}, {
            flesh: 1,
            flesh_fields: {acplgm: ['location']},
            order_by: {acplgm: ['location']}
        }).pipe(finalize(() => this._loadingGroupEntries = false))
            .subscribe(data => {
                data.name = data.location().name();
                data.shortname = this.org.get(data.location().owning_lib()).shortname();
                // remove all non-alphanumeric chars to make label a valid id
                data.label = (data.shortname + data.name).replace(/\W/g, '');
                data.checked = false;
                this.groupEntries.push(data);
            }, (error: unknown) => {
                console.debug(error);
            }, () => {
                this.loadShelvingLocations();
            });
    };

    loadShelvingLocations = () => {
        if (this._loadingShelvingLocations) {return;}
        this._loadingShelvingLocations = true;
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
            .pipe(finalize(() => this._loadingShelvingLocations = false))
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
                if (!data.hidden) {this.shelvingLocations.push(data);}
            }, (error: unknown) => {
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
    };

    addEntryCount() {
        if (this.entriesToAdd() && this.entriesToAdd().length > 0) {return this.entriesToAdd().length;}
    }

    entriesToAdd() {
        if (!this.shelvingLocations) {return;}

        return this.shelvingLocations.filter((entry) => {
            return entry.checked;
        });
    }

    addEntries = () => {
        const checkedEntries = this.entriesToAdd();
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
                (err: unknown) => {
                    console.debug(err);
                    this.addedGroupEntriesFailure.current().then(msg => this.toast.warning(msg));
                }
            );
        });
    };

    removeEntryCount() {
        if (this.entriesToRemove() && this.entriesToRemove().length > 0) {return this.entriesToRemove().length;}
    }

    entriesToRemove() {
        if (!this.groupEntries) {return;}

        return this.groupEntries.filter((entry) => {
            return entry.checked;
        });
    }

    removeEntries = () => {
        const checkedEntries = this.entriesToRemove();
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
            }, (error: unknown) => {
                console.debug(error);
                this.removedGroupEntriesFailure.current().then(msg =>
                    this.toast.warning(msg));
            }
        );
    };

    orgOnChange = (org: IdlObject): void => {
        this.selectedOrg = org;
        this.selectedOrgId = org.id();
        this.loadLocationGroups();
        this.checkCurrentPermissions();
    };

    moveUp($event, group, index) {
        $event.preventDefault();
        if (index === 0) {
            return;
        }

        this.draggedElement = group;
        this.assignNewPositions(index, index - 1);
        setTimeout(() => $event.target.focus(), 0);
    }

    moveDown($event, group, index) {
        $event.preventDefault();
        if (index === this.locationGroups.length - 1) {
            return;
        }

        this.draggedElement = group;
        this.assignNewPositions(index, index + 1);
        setTimeout(() => $event.target.focus(), 0);
    }

    onDragStart = (event, locationGroup) => {
        this.draggedElement = locationGroup;
    };

    onDragOver = (event) => {
        event.preventDefault();
    };

    onDragEnter = (event, locationGroup) => {
        this.dragTarget = locationGroup;
    };

    onDragDrop = (event, index) => {
        // do nothing if element is dragged onto itself
        if (this.draggedElement === this.dragTarget) {
            this.dragTarget = null;
            return;
        }

        const moveFrom = this.locationGroups.indexOf(this.draggedElement);
        const moveTo = this.locationGroups.indexOf(this.dragTarget);
        // clear styles before everything else
        this.draggedElement = null;
        this.dragTarget = null;
        this.assignNewPositions(moveFrom, moveTo);
    };

    assignNewPositions(moveFrom, moveTo) {
        if (moveTo > this.locationGroups.length) {
            moveTo = this.locationGroups.length;
        }
        // console.debug("Moving ", moveFrom, " to ", moveTo);
        this.locationGroups.splice(moveTo, 0, this.locationGroups.splice(moveFrom, 1)[0]);

        // find the position of the group before the first one we changed
        let newPosition = -1;
        const firstIndex = Math.min(moveFrom, moveTo);
        if (firstIndex > 0) {
            newPosition = this.locationGroups[firstIndex - 1].posit;
        }

        const lastIndex = Math.max(moveFrom, moveTo);

        const locationGroupsToUpdate = [];
        // add 1 to the position of all groups from the earliest one we changed
        for (let i = firstIndex; i <= lastIndex; i++) {
            newPosition++;
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
            (err: unknown) => {
                console.debug(err);
                errorHappened = true;
            },
            () => {
                this.sortLocationGroups();
                if (errorHappened) {
                    this.changeOrderFailure.current().then(msg => {
                        this.toast.warning(msg);
                        console.debug(msg);
                    });
                } else {
                    this.changeOrderSuccess.current().then(msg => {
                        this.toast.success(msg);
                        console.debug(msg);
                    });
                }
            }
        );
    }
}
