import { None, Some } from './maybe';

describe('Maybe', () => {
    describe('whenSome', () => {
        it('only runs when it is Some', () => {
            let changed1 = false;
            let changed2 = false;

            new Some<string>('dog').whenSome(() => changed1 = true);
            new None<String>().whenSome(() => changed2 = true);

            expect(changed1).toBeTrue();
            expect(changed2).toBeFalse();
        });

        it('can chain', () => {
            let changed1 = false;
            let changed2 = false;

            new Some<string>('dog')
                .whenSome(() => changed1 = true)
                .whenSome(() => changed2 = true);

            expect(changed1).toBeTrue();
            expect(changed2).toBeTrue();

        });

        it('provides the value to the callback in the Some variant', () => {
            let myAnimal = 'cat';
            new Some<string>('dog').whenSome(animal => myAnimal = animal);
            expect(myAnimal).toEqual('dog');
        });
    });
});
