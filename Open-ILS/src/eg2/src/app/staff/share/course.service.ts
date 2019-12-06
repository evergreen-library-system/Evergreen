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
        return new Promise((resolve, reject) => {
            this.org.settings('circ.course_materials_opt_in').then(res => {
                resolve(res['circ.course_materials_opt_in']);
            });
        });
    }
    getCourses(course_ids?: Number[]): Promise<IdlObject[]> {
        if (!course_ids) {
            return this.pcrud.retrieveAll('acmc',
                {}, {atomic: true}).toPromise();
        } else {
            return this.pcrud.search('acmc', {id: course_ids},
                {}, {atomic: true}).toPromise();
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

    fleshMaterial(itemId, relationship?): Promise<any> {
        return new Promise((resolve, reject) => {
            let item = this.idl.create('acp');
            this.net.request(
                'open-ils.circ',
                'open-ils.circ.copy_details.retrieve',
                this.auth.token(), itemId
            ).subscribe(res => {
                if (res && res.copy) {
                    item = res.copy;
                    item.call_number(res.volume);
                    item._title = res.mvr.title();
                    item.circ_lib(this.org.get(item.circ_lib()));
                    if (relationship) item._relationship = relationship;
                }
            }, err => {
                reject(err);
            }, () => resolve(item));
        });
    }

    getCoursesFromMaterial(copy_id): Promise<any> {
        let id_list = [];
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

    fetchCopiesInCourseFromRecord(record_id) {
        let cp_list = [];
        let course_list = [];
        return new Promise((resolve, reject) => {
            this.net.request(
                'open-ils.cat',
                'open-ils.cat.asset.copy_tree.global.retrieve',
                this.auth.token(), record_id
            ).subscribe(copy_tree => {
                copy_tree.forEach(cn => {
                    cn.copies().forEach(cp => {
                        cp_list.push(cp.id());
                    });
                });
            }, err => reject(err),
            () => {
                resolve(this.getCoursesFromMaterial(cp_list));
            });
        });
    }

    // Creating a new acmcm Entry
    associateMaterials(item, args) {
        let material = this.idl.create('acmcm');
        material.item(item.id());
        if (item.call_number() && item.call_number().record()) {
            material.record(item.call_number().record());
        }
        material.course(args.currentCourse.id());
        if (args.relationship) material.relationship(args.relationship);

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
            if (!args.tempCircMod) item.circ_modifier(null);
        }
        if (args.isModifyingCallNumber) {
            material.original_callnumber(item.call_number());
        }
        let response = {
            item: item,
            material: this.pcrud.create(material).toPromise()
        };

        return response;
    }

    disassociateMaterials(courses) {
        return new Promise((resolve, reject) => {
            let course_ids = [];
            let course_library_hash = {};
            courses.forEach(course => {
                course_ids.push(course.id());
                course_library_hash[course.id()] = course.owning_lib();
            });
            this.pcrud.search('acmcm', {course: course_ids}).subscribe(material => {
                material.isdeleted(true);
                this.resetItemFields(material, course_library_hash[material.course()]);
                this.pcrud.autoApply(material).subscribe(res => {
                }, err => {
                    reject(err);
                }, () => {
                    resolve(material);
                });
            }, err => {
                reject(err)
            }, () => {
                resolve(courses);
            });
        });
    }

    resetItemFields(material, course_lib) {
        this.pcrud.retrieve('acp', material.item(),
            {flesh: 3, flesh_fields: {acp: ['call_number']}}).subscribe(copy => {
            if (material.original_status()) {
                copy.status(material.original_status());
            }
            if (copy.circ_modifier() != material.original_circ_modifier()) {
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

    updateItem(item: IdlObject, course_lib, call_number, updatingVolume) {
        return new Promise((resolve, reject) => {
            this.pcrud.update(item).subscribe(item_id => {
                if (updatingVolume) {
                    let cn = item.call_number();
                    return this.net.request(
                        'open-ils.cat', 'open-ils.cat.call_number.find_or_create',
                        this.auth.token(), call_number, cn.record(),
                        course_lib, cn.prefix(), cn.suffix(),
                        cn.label_class()
                    ).subscribe(res => {
                        let event = this.evt.parse(res);
                        if (event) return;
                        return this.net.request(
                            'open-ils.cat', 'open-ils.cat.transfer_copies_to_volume',
                            this.auth.token(), res.acn_id, [item.id()]
                        ).subscribe(transfered_res => {
                            console.debug("Copy transferred to volume with code " + transfered_res);
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
                    this.pcrud.update(item).subscribe(rse => {
                        resolve(item);
                    }, err => {
                        reject(item);
                    });
                }
            });
        });
    }

}