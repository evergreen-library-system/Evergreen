// A higher-order function: it accepts a function as its input
// that is used as criteria, and returns a function that can
// check an array and confirm that none of its elements match
// the criteria.
export function noSuch<Element>(criteria: (one: Element) => boolean): ((all: Element[]) => boolean) {
    return (all: Element[]) => !all.some(criteria);
}
