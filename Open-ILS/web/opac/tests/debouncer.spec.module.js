import { Debouncer } from "../../js/ui/default/opac/debouncer.module.js";


describe("Debouncer", () => {
    describe("#debounce", () => {
        it("waits the specified amount of time to call the function", async () => {
            jasmine.clock().install();
            const myFunction = jasmine.createSpy();
            new Debouncer().debounce(myFunction, 200)();
            expect(myFunction).not.toHaveBeenCalled();
            jasmine.clock().tick(250);
            expect(myFunction).toHaveBeenCalled();
            jasmine.clock().uninstall();
        });
    });
});
