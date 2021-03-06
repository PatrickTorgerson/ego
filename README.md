# ego

[![License](https://img.shields.io/apm/l/atomic-design-ui.svg?)](https://github.com/PatrickTorgerson/ego/blob/main/LICENSE)
[![Last Commit](https://img.shields.io/github/last-commit/PatrickTorgerson/ego)](https://github.com/PatrickTorgerson/ego/commits/main)
[![Code Size](https://img.shields.io/github/languages/code-size/PatrickTorgerson/ego)](https://github.com/PatrickTorgerson/ego)

Small toy interpreted scripting language written in Zig

## Example

> NOTE : This is a proposed syntax and is subject to change.
>       Currently only a basic virtual machine is implemented

```go
type vec2 = struct
    x,y numeric

method vec2::lensqrd() numeric
    return .x * .x + .y * .y

method vec2::len() numeric
    return math.sqrt(.lensqrd())

var pos = vec2: 1,1
assert(pos.len() == 1.4142)
```

## Licence

> MIT License
>
> Copyright (c) 2022 Patrick Torgerson
>
> Permission is hereby granted, free of charge, to any person obtaining a copy
> of this software and associated documentation files (the "Software"), to deal
> in the Software without restriction, including without limitation the rights
> to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
> copies of the Software, and to permit persons to whom the Software is
> furnished to do so, subject to the following conditions:
>
> The above copyright notice and this permission notice shall be included in all
> copies or substantial portions of the Software.
>
> THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
> IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
> FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
> AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
> LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
> OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
> SOFTWARE.
