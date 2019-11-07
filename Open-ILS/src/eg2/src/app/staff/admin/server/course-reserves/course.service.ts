import {AuthService} from '@eg/core/auth.service';
import {EventService} from '@eg/core/event.service';
import {IdlObject, IdlService} from '@eg/core/idl.service';
import {NetService} from '@eg/core/net.service';
import {PcrudService} from '@eg/core/pcrud.service';

export class CourseService {

    constructor(
        private auth: AuthService,
        private evt: EventService,
        private idl: IdlService,
        private net: NetService,
        private pcrud: PcrudService
    ) {}

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
                    console.log(res);
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
                    return this.pcrud.update(item);
                }
            });
        });
    }

}