# ego

[![License](https://img.shields.io/github/license/PatrickTorgerson/ego)](https://github.com/PatrickTorgerson/ego/blob/main/LICENSE)
[![Last Commit](https://img.shields.io/github/last-commit/PatrickTorgerson/ego)](https://github.com/PatrickTorgerson/ego/commits/main)
[![Code Size](https://img.shields.io/github/languages/code-size/PatrickTorgerson/ego)](https://github.com/PatrickTorgerson/ego)

Custom programming language for learning and for fun

## Example

> NOTE : This is a proposed syntax and is subject to change.
>       Currently only basic variable declarations are being parsed

```rust
pub type Vec2 = struct {
    x,y f64
}

pub fn |Vec2| lensqrd() f64 {
    return .x * .x + .y * .y;
}

pub fn |Vec2| len() f64 {
    return ego::sqrt(.lensqrd());
}

pub fn |mut Vec2| normalize() {
    const len = .len();
    .x /= len;
    .y /= len;
}

pub fn main() {
    const pos = Vec2: 1,1;
    assert pos.len() == 1.4142;
    pos.normalize();
    assert pos.len() == 1;
}
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
