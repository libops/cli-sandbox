Object.defineProperty(process.stdin, 'isTTY', {
    value: true,
    writable: false,
    enumerable: true,
    configurable: true
});
