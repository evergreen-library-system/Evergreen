import { apply_adv_copy_locations } from "../../js/ui/default/opac/copyloc.module.js";
import { JSDOM } from '../deps/node_modules/jsdom/lib/api.js';

function mockGlobals(location_group_selected=false) {
    const { window } = new JSDOM(`<!DOCTYPE html>
      <select id="adv_org_selector" class="form-control w-100" title="Select Library" name="locg">
        <option value="1" class="org_unit">My nice consortium</option>
        <option value="105" ${location_group_selected ? '' : 'selected'} class="org_unit">My nice library</option>
        <option value="1:4" ${location_group_selected ? 'selected' : ''} class="loc_grp">Teen books</option>
      </select>
      <div id="adv_chunk_copy_location">
        <div id="adv_copy_location_selector_new"></div>
      </div>
      <div id="adv_copy_location_selector"></div>
    `);
    global.window = window;
    global.window.aou_hash = {
        1: {
            "id": "1",
            "name": "My nice consortium",
            "parent_ou": "",
            "depth": "0",
            "can_have_vols": "f"
        },
        105: {
            "id": "105",
            "name": "My nice library",
            "parent_ou": "102",
            "depth": "2",
            "can_have_vols": "t"
        },
        102: {
            "id": "102",
            "name": "My nice system",
            "parent_ou": "1",
            "depth": "1",
            "can_have_vols": "f"
        }
    };
    const sampleContentByOrgId = [
        {
        "owning_lib": 1,
        "name": "DVDs",
        "id": 106
        },
        {
        "name": "Young adult",
        "owning_lib": 1,
        "id": 105
        },
        {
        "id": 103,
        "owning_lib": 1,
        "name": "Reference"
        }
    ];
    const sampleContentByGroup = [
        {
        "owning_lib": 1,
        "name": "Teen non-fiction",
        "id": 112
        },
        {
        "name": "Young adult",
        "owning_lib": 1,
        "id": 105
        },
        {
        "id": 110,
        "owning_lib": 1,
        "name": "Teen fiction"
        }
    ];
    const mockClientSession = class ClientSession {
        request(details) {
            details.oncomplete({
                recv: () => {
                    return {content: () => details.params[0].query.owning_lib ? sampleContentByOrgId : sampleContentByGroup};
                }
            });
            return {send: () => true};
        }
    };
    global.window.OpenSRF = {
        ClientSession: mockClientSession
    };
    global.document = global.window.document;
}


describe('apply_adv_copy_locations()', () => {
    describe('for the bootstrap opac', () => {
        it('adds the correct copy locations as checkboxes to the #adv_copy_location_selector_new element', () => {
            mockGlobals();

            apply_adv_copy_locations();
            const checkboxes = global.document.querySelectorAll('#adv_copy_location_selector_new input[type=checkbox]');

            expect(checkboxes.length).toBe(3);
            expect(checkboxes[0].getAttribute('value')).toBe('106');
            expect(checkboxes[0].parentElement.textContent.trim()).toBe('DVDs');

            expect(checkboxes[1].getAttribute('value')).toBe('103');
            expect(checkboxes[1].parentElement.textContent.trim()).toBe('Reference');

            expect(checkboxes[2].getAttribute('value')).toBe('105');
            expect(checkboxes[2].parentElement.textContent.trim()).toBe('Young adult');
        });
        describe('when a shelving location group is selected', () => {
            it('includes shelving locations from within that group', () => {
                mockGlobals(true);

                apply_adv_copy_locations();
                const checkboxes = global.document.querySelectorAll('#adv_copy_location_selector_new input[type=checkbox]');

                expect(checkboxes.length).toBe(3);
                expect(checkboxes[0].getAttribute('value')).toBe('110');
                expect(checkboxes[0].parentElement.textContent.trim()).toBe('Teen fiction');

                expect(checkboxes[1].getAttribute('value')).toBe('112');
                expect(checkboxes[1].parentElement.textContent.trim()).toBe('Teen non-fiction');

                expect(checkboxes[2].getAttribute('value')).toBe('105');
                expect(checkboxes[2].parentElement.textContent.trim()).toBe('Young adult');
            });
        });
    });
    describe('for the tpac opac', () => {
        it('adds the correct copy locations as options to the #adv_copy_location_selector element', () => {
            mockGlobals();

            apply_adv_copy_locations();
            const options = global.document.querySelectorAll('#adv_copy_location_selector option');

            expect(options.length).toBe(3);
            expect(options[0].getAttribute('value')).toBe('106');
            expect(options[0].textContent.trim()).toBe('DVDs');

            expect(options[1].getAttribute('value')).toBe('103');
            expect(options[1].textContent.trim()).toBe('Reference');

            expect(options[2].getAttribute('value')).toBe('105');
            expect(options[2].textContent.trim()).toBe('Young adult');
        });
    });
});

