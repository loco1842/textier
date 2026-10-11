# Hand-written JSON parser and pretty-printer

textier must find JSON objects and arrays embedded anywhere inside arbitrary text, preserve the original key order when beautifying (log payloads are read by humans who expect the order they were logged in), and detect JSON escaped inside string values. Foundation's `JSONSerialization` does none of these: it parses whole documents only and reorders keys. So `TextierCore` carries its own scanner, parser and pretty-printer, and `JSONSerialization` is not used for anything the user sees. Switching back would silently lose key order.
