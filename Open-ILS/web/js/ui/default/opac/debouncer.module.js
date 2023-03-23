export class Debouncer {
    debounce(functionToDebounce, milliseconds) {
        let timer;
        return(...args) => {
            clearTimeout(timer);
            timer = setTimeout(() => {
                functionToDebounce.apply(args);
            }, milliseconds);
        };
    }
}
