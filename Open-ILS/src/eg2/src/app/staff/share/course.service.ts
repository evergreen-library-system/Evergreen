import {Observable} from 'rxjs';
import {tap} from 'rxjs/operators';
import {Injectable} from '@angular/core';
import {AuthService} from '@eg/core/auth.service';
import {EventService} from '@eg/core/event.service';
import {IdlObject, IdlService} from '@eg/core/idl.service';
import {NetService} from '@eg/core/net.service';
import {OrgService} from '@eg/core/org.service';
import {PcrudService} from '@eg/core/pcrud.service';

@Injectable()
export class CourseService {

    constructor(
        private auth: AuthService,
        private evt: EventService,
        private idl: IdlService,
        private net: NetService,
        private org: OrgService,
        private pcrud: PcrudService
    ) {}

    isOptedIn(): Promise<any> {
        return new Promise((resolve) => {
            this.org.settings('circ.course_materials_opt_in').then(res => {
                resolve(res['circ.course_materials_opt_in']);
            });
        });
    }
    getCourses(course_ids?: Number[]): Promise<IdlObject[]> {
        const flesher = {flesh: 2, flesh_fields: {
            'acmc': ['owning_lib'],
            'aou': ['ou_type']}};
        if (!course_ids) {
            return this.pcrud.retrieveAll('acmc',
                flesher, {atomic: true}).toPromise();
        } else {
            return this.pcrud.search('acmc', {id: course_ids},
                flesher, {atomic: true}).toPromise();
        }
    }

    getMaterials(course_ids?: Number[]): Promise<IdlObject[]> {
        if (!course_ids) {
            return this.pcrud.retrieveAll('acmcm',
                {}, {atomic: true}).toPromise();
        } else {
            return this.pcrud.search('acmcm', {course: course_ids},
                {}, {atomic: true}).toPromise();
        }
    }

    getUsers(course_ids?: Number[]): Observable<IdlObject> {
        const flesher = {
            flesh: 1,
            flesh_fields: {'acmcu': ['usr', 'usr_role']}
        };
        if (!course_ids) {
            return this.pcrud.retrieveAll('acmcu',
                flesher);
        } else {
            return this.pcrud.search('acmcu', {course: course_ids},
                flesher);
        }
    }

    getCoursesFromMaterial(copy_id): Promise<any> {
        const id_list = [];
        return new Promise((resolve, reject) => {

            return this.pcrud.search('acmcm', {item: copy_id})
            .subscribe(materials => {
                if (materials) {
                    id_list.push(materials.course());
                }
            }, err => {
                console.debug(err);
                reject(err);
            }, () => {
                if (id_list.length) {
                    return this.getCourses(id_list).then(courses => {
                        resolve(courses);
                    });
                }
            });
        });
    }

    fetchCoursesForRecord(recordId) {
        const courseIds = new Set<number>();
        return this.pcrud.search(
            'acmcm', {record: recordId}, {atomic: false}
        ).pipe(tap(material => {
            courseIds.add(material.course());
        })).toPromise()
        .then(() => {
            if (courseIds.size) {
                return this.getCourses(Array.from(courseIds));
            }
        });
    }

    // Creating a new acmcm Entry
    associateMaterials(item, args) {
        const material = this.idl.create('acmcm');
        material.item(item.id());
        if (item.call_number() && item.call_number().record()) {
            material.record(item.call_number().record());
        }
        material.course(args.currentCourse.id());
        if (args.relationship) { material.relationship(args.relationship); }

        // Apply temporary fields to the item
        if (args.isModifyingStatus && args.tempStatus) {
            material.original_status(item.status());
            item.status(args.tempStatus);
        }
        if (args.isModifyingLocation && args.tempLocation) {
            material.original_location(item.location());
            item.location(args.tempLocation);
        }
        if (args.isModifyingCircMod) {
            material.original_circ_modifier(item.circ_modifier());
            item.circ_modifier(args.tempCircMod);
            if (!args.tempCircMod) { item.circ_modifier(null); }
        }
        if (args.isModifyingCallNumber) {
            material.original_callnumber(item.call_number());
        }
        const response = {
            item: item,
            material: this.pcrud.create(material).toPromise()
        };

        return response;
    }

    associateUsers(patron_id, args) {
        const new_user = this.idl.create('acmcu');
        if (args.role) { new_user.usr_role(args.role); }
        new_user.course(args.currentCourse.id());
        new_user.usr(patron_id);
        return this.pcrud.create(new_user).toPromise();
    }

    disassociateMaterials(courses) {
        return new Promise((resolve, reject) => {
            const course_ids = [];
            const course_library_hash = {};
            courses.forEach(course => {
                course_ids.push(course.id());
                course_library_hash[course.id()] = course.owning_lib();
            });
            this.pcrud.search('acmcm', {course: course_ids}).subscribe(material => {
                material.isdeleted(true);
                this.resetItemFields(material, course_library_hash[material.course()]);
                this.pcrud.autoApply(material).subscribe(() => {
                }, err => {
                    reject(err);
                }, () => {
                    resolve(material);
                });
            }, err => {
                reject(err);
            }, () => {
                resolve(courses);
            });
        });
    }

    disassociateUsers(user) {
        return new Promise((resolve, reject) => {
            const user_ids = [];
            const course_library_hash = {};
            user.forEach(course => {
                user_ids.push(course.id());
                course_library_hash[course.id()] = course.owning_lib();
            });
            this.pcrud.search('acmcu', {user: user_ids}).subscribe(u => {
                u.course(user_ids);
                this.pcrud.autoApply(user).subscribe(res => {
                    console.debug(res);
                }, err => {
                    reject(err);
                }, () => {
                    resolve(user);
                });
            }, err => {
                reject(err);
            }, () => {
                resolve(user_ids);
            });
        });
    }

    resetItemFields(material, course_lib) {
        this.pcrud.retrieve('acp', material.item(),
            {flesh: 3, flesh_fields: {acp: ['call_number']}}).subscribe(copy => {
            if (material.original_status()) {
                copy.status(material.original_status());
            }
            if (copy.circ_modifier() !== material.original_circ_modifier()) {
                copy.circ_modifier(material.original_circ_modifier());
            }
            if (material.original_location()) {
                copy.location(material.original_location());
            }
            if (material.original_callnumber()) {
                this.pcrud.retrieve('acn', material.original_callnumber()).subscribe(cn => {
                    this.updateItem(copy, course_lib, cn.label(), true);
                });
            } else {
                this.updateItem(copy, course_lib, copy.call_number().label(), false);
            }
        });
    }


    updateItem(item: IdlObject, courseLib, callNumber, updatingVolume) {
        return new Promise((resolve, reject) => {
            this.pcrud.update(item).subscribe(() => {
                if (updatingVolume) {
                    const cn = item.call_number();
                    const callNumberLibrary = this.org.canHaveVolumes(courseLib) ? courseLib.id() : cn.owning_lib();
                    return this.net.request(
                        'open-ils.cat', 'open-ils.cat.call_number.find_or_create',
                        this.auth.token(), callNumber, cn.record(),
                        callNumberLibrary, cn.prefix(), cn.suffix(),
                        cn.label_class()
                    ).subscribe(res => {
                        const event = this.evt.parse(res);
                        if (event) { return; }
                        return this.net.request(
                            'open-ils.cat', 'open-ils.cat.transfer_copies_to_volume',
                            this.auth.token(), res.acn_id, [item.id()]
                        ).subscribe(transfered_res => {
                            console.debug('Copy transferred to volume with code ' + transfered_res);
                        }, err => {
                            reject(err);
                        }, () => {
                            resolve(item);
                        });
                    }, err => {
                        reject(err);
                    }, () => {
                        resolve(item);
                    });
                } else {
                    this.pcrud.update(item).subscribe(() => {
                        resolve(item);
                    }, () => {
                        reject(item);
                    });
                }
            });
        });
    }

}
