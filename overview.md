# ego overview

> Disclamer : ego is under active design/development. All syntax is subject to change.
>             Currently the repo can only do some basic lexing.

ego is an interperated language with [gradual typing](https://en.wikipedia.org/wiki/Gradual_typing).
Variables can be statically typed and participate in static type checking, or dynamcally typed where type
errors will be checked and reported at runtime.

---

## contents

- [variables](#variables)
- [references](#references)
- [optionals](#optionals)
- [literals](#literals)
- [arrays](#arrays)
- [lists](#lists)
- [maps](#maps)
- [conrol flow](#controlflow)
    - [code blocks](#controlflow_blocks)
    - [if](#controlflow_if)
    - [switch](#controlflow_switch)
    - [for](#controlflow_for)
    - [func](#controlflow_func)
    - [explicit block ends](#controlflow_end)
- [user defined types](#usertypes)
    - [structure](#usertypes_struct)
    - [interface](#usertypes_interface)
    - [enumeration](#usertypes_enum)
- [namespacing](#namespacing)
- [methods](#methods)

<a name="variables"></a>

---

## variables

Variables are declared with `var` or `const`. The type of a variable infered.

```go
var hello = "world" // `hello` is constrained to `string`
hello = 4 // error: expected string

const twelve = 12
twelve = 69 // error: cannot asign to constant
```

You can asign to muliple variables at once

```go
var x,y,z = 1, 2, "a string"

// a,b, and c are all int's initialized to 0
// if a variable declaration statement has exactly one initializer
// it will be used to initialze all variable being declared
var a,b,c = 0

// if a variable declaration statement has more than one initializer
// there must be exactly one initializer per variable being declared
var i,j,k = 0,0 // ERR not enough initializers
var i,j,k = 0,0,0,0 // ERR too many initializers

// swap values
x,y = y,x
```

ego supports the following builtin types:

- `int` : 64 bit signed integer
- `float` : 64 bit floating point
- `bool` : 8 bit boolean `true` or `false`
- `string` : UTF-8 string
- `byte` : 8 bit unsigned int
- `codepoint` : 32 bit Unicode codepoint

ego also supports several builtin container types:

- `arrays`: fixed sized sequence of simalarly typed values
- `list`: dynamically sized array
- `map`: dynamically sized table of key value pairs

<a name="references"></a>

## references

> TODO

```go
var a = 1
var r = &a
```

<a name="optionals"></a>

## optionals

> TODO

optional types can be asigned nil

```go
var a = ?int: 10
var a = ?10 // infered optional int
a = nil

// special if that can unwrap optionals
if a |val|
    assert(val == 10)
else
    assert(val == nil)

func get_value() ?int
    if exists : return 12
    else: return nil
```

<a name="literals"></a>

## literals

Integer literals
```rust
-10      // decimal
-0b00    // binary int
-0x00    // hex int
-0o00    // octal int
```

Floating point literals
```rust
-3.1415
1.1234e24
1.0e-10
```

Numeric literals may contain apostrophies
```rust
1'000
100'000'000.75
```

Typed literals take the form a type expression followed by a block of initializers
```go
const pi = float: 3.1415926
const pos = vec2: 0,0

const author = Person
    .name = "patrick"
    .birth_year = 1997
```

<a name="arrays"></a>

## arrays

> TODO

```go

// array with constant length (stored on stack)
var a = [100]int: 1, 2, 3, 0...
a = [100]int: 1...
a = [50]int: 2... // error: expected [100]int found [50]int

// array with constant length (stored on heap)
var a = &[69]string: ""...

// array with runtime length (stored on heap)
var buffer = [_]int: _
buffer = [100]int: 0... // ok
buffer = [50]int: 0... // ok

// runtime size, initially 20
var data = [_]int: 0 ** 20

var siblings = [_]Person
    : "Cody", 1995
    : "Patrick", 1997
    : "Madelyn", 1998
    : "Sarah", 2002


// resize
var new = [300]int: _
const len = ego::min(a.len, new.len)
for i in ego::range(len)
    b[i] = a[i]
a = new

```

<a name="lists"></a>

## lists

> TODO

```go
var l = list(int): 1,2,3,4,5
l.append(77)

for v,i in l
    l[i] = v * 2

var back = l.pop()
assert(back == 154)
```

<a name="maps"></a>

## maps

> TODO

```go
const m = map(string,any)
    "name"  =  "Mayday Monday"
    "month" = 5
    "day"   = 26
    "first" = 1997

for k,v in m
    print "{k} = {v}"
```

<a name="controlflow"></a>

## control flow

> TODO

<a name="controlflow_blocks"></a>

### code blocks

> TODO

```go
block // anonymous blocks
    var a = 12
    print "a = {a}"
print "a = {a}" // ERR variable `a` is out of scope

block b // named block
    // ...
    if done: break b
    /// ...

// use a colon for singl-line blocks
block: print "why is this a block?"
```

<a name="controlflow_if"></a>

### if

> TODO

```go
if condition
    print "if block"
else if condition
    print "else if block"
else
    print "else block"
```

<a name="controlflow_switch"></a>

### switch

> TODO

```go
const i = get_value()

switch i
    case 0 : print "i == 0"

    case 1,2,3
        print "colons are only for single-line blocks"

    case 4..40 : print "ranges are neat"

    else: print "No other cases matched"
    case: print ":(" // ERR case blocks connot appear after else block
```

<a name="controlflow_for"></a>

### for

> TODO

```go
// loop while condition is true
for condition
    print "true"

// continuation_expr executed after every iteration
for condition; continuation_expr
    print "true"

// iterate over a sequence
var array = [_]int: 1,2,3,4,5
for val in array
    print "iteration {val}"

for val,i in array
    print "array[{i}] = {val}"
```

<a name="controlflow_func"></a>

### func

> TODO

function parameters are immutable

```go
func name(param param_type) return_type
    return value

// use references to mutate calling code's data
func write_12(dest &int) void
    dest = 12

// use ':' for single line block
// return type can be infered
// params can be grouped by type
func add(a,b int) : return a + b
```

<a name="controlflow_end"></a>

### explicit block ends

> TODO

```go
func hello()
end hello

if true
end if

for i in ints
end for

block
    print "yo"
end block

type cosa = struct
    name string
    birthyear int
    height int
end struct

var c = cosa
    name = "Bean Pole"
    birthyear = 1977
    height = 12
end cosa

```

<a name="usertypes"></a>

## user defined types

User defined types are declared with the `type` keyword. Types in eqo are split into two catagories;
Concrete Types, and Abstract types. A concrete type can represent all possible values with a single base type, whereas the underlying type of an abstract type could vary depending on the current value.

<a name="usertypes_alias"></a>

### aliasing

A type alias provides a new name for an existing type.

```go
type i64 = int
type namelist = list(string)
```

<a name="usertypes_typeset"></a>

### type set

A type set describes an abstract type that can represent values from two or more types.

```go
type numeric = int | float
```

<a name="usertypes_valueset"></a>

### value set

A value set describes a type that can represent one value from a set of values. The type
is concrete if all values can be represented with a single type.

```go
type mybool = true | false
type direction = "north" | "south" | "east" | "west"
type optional_int = nil | int
```

<a name="usertypes_valuerange"></a>

### value range

Like a value set but specify a range of values.

```go
type month = 1..12
type uint = 0..ego::max_value(int)
type ascii = 0..127

type digit = '0'..'9'
type lower = 'a'..'z'
type upper = 'A'..'Z'
type alpha = lower | upper
type alphanumeric = alpha | digit
```

<a name="usertypes_struct"></a>

### structure

A struct is a statically sized sequence of named values. They can be declared with the `struct` keyword,
followed by a block of field declarations.

```go
type person = struct
    name string
    age int
    height int
    alive bool = true // optional default initializer
```

Struct values can be created with a struct literal. Specify the name of the struct, then a block of field initilizers

```go
// all fields must be initialized
// fields with defualt initializers can be omitted
var p = person
    .name = "Patrick"
    .age = 25
    .height = 173

// name designations are optional
// initializers are assigned to fields in order of declaration
var p = person
    "patrick"
    25
    173

// use commas to declare initializers on the same line
var p = person
    "patrick", 25, 173

// use single line block
var p = person: "patrick", 25, 173
```

Standard member access syntax

```go
print "{p.name}" // Patrick
p.name = "Horatio Slim"
print "{p.name}" // Horatio Slim
```

Structs can be destructured,
and tuples can be structured into structs

```go
// destructuring
var name,age,height,alive = p
// structuring
p = "Wanda", 500, 35, true

print "{name}" // Horatio Slim
print "{p.name}" // Wanda
```

<a name="usertypes_interface"></a>

### interface

An interface defines a type by the [methods](#methode) it must implement. They are declared with the `interface` keyword
followed by a block of [method](#methode) signitures.

```go
type Serial = interface
    serialize() string
    deserialize(string) &.type

    // maybe C++20 style requires expressions?
    // requires(t .type) : t == t.deserialize(t.serialize())

    // maybe default implementations?

fn |file| write_value(value Serial)
    .write_string(value.serialize())
```

To have a type support an interface simply implement the necessary [methods](#methods).
If you want to ensure a particular interface is implemented on a given type you can use the `is` operator.

```go
fn |person| serialize() string
    return fmt "person: .name='{.name}', .age={.age}, .height={.height}, .alive={.alive};"

fn |&person| deserialize(str string) &person
    this = scan str "person: .name='{:s}', .age={:d}, .height={:d}, .alive={:b};"
    return this

assert(person is serial)
```

You can also require another interface be implemented

```go
type List = interface
    interface Serial
    size() int
```

<a name="usertypes_enum"></a>

### enumeration

> TODO

An enumeration is an enumeration. enumeration.

```go
type Direction = enum
    north, south
    east, west

var dir = Direction.north
```

<a name="namespacing"></a>

## namespacing

Declarations can be added to a namespace by preceding it's name with a namespace specifier.

```go
const math::pi = 3.1415

func math::square(n numeric) numeric : return n*n
```

<a name="methods"></a>

## methods

ego does not have classes. However, you can define methods on types.
A method is a function with a special receiver type.
The receiver appears between the func keyword and the method name
these functions can be called on a value with a period. A reference to the
value the method is being called on can be obtained with the `this` keyword. If the value
is of struct type, member access can can have the `this` keyword omited. `this.age == .age`

```go
func |person| output()
    if .alive
        print "person: {.name}, {.age} years, {.height}cm"
    else
        print "RIP {.name}"

p.output() // person: Wanda, 500 years, 35cm
(person: "Bob",0,0,false).output() // RIP Bob

// 'this' reference is immutable by defualt
func |person| happy_birthday()
    .age += 1 // ERR connot assign to member of immutable reference `this`

// use an ampersand for mutable this
func |&person| happy_birthday()
    .age += 1 // OK `this` is mutable

func |int| squared()
    return this * this

func |[]int| sum()
    var v = 0
    for v in this
        s += v
    return v

const sqr = 5.squared() // 25
const sum = [1,2,3,4,5,6].sum()
```


# playin

```go

import math
pub import math

using import math
pub using import math

namespace m = import math
pub namespace m = import math

import math::BigInteger

import gui/components/button::Button

type Buffer = import buffer::Buffer
fn init = import buffer::init

fn assert = ego::assert

namespace m
    namespace m = import math

var path = ego::path: resource/image/buddy.png

```

```rust

// integer division
const i = 41

i = i / 2 // error: expected int found float (integer division results in float)
i = round(i/2)
i = floor(i/2)
i = ceil(i/2)
i = trunc(i/2)

const f = ego::pi

f = float(i)

type Cosa = struct
    age &int

var age = 10
var c = &Cosa: &age
var a = &c.age // redundant &&age == &age



pub type Buffer = (import buffer.ego)::Buffer

pub type Vec2 = struct
    x,y float
    pub fn init_polar(angle,magnitude float)
        var self = Vec2:
            .x = ego::cos(angle)
            .y = ego::sin(angle)
        return ::mul(self, magnitude)
    pub fn add(l,r Vec2) Vec2
        return Vec2
            .x = l.x + r.x
            .y = l.y + r.y
    pub fn mul(v Vec2, s numeric) Vec2
        return Vec2
            .x = v.x * s
            .y = v.y * s
    pub fn |Vec2| length()
        return ego::sqrt(.x * .x + .y * .y)
    pub fn |Vec2| mul(s numeric)
        this = ::mul(this, s)
end struct Vec2

const polar = Vec2::init_polar(
    .angle = ego::pi * 2.0
    .magnitude = 100.0
)

const a = Vec2: default
const b = Vec2: 10,11
const c = Vec2::add(a,b)

ego::assert(c.x == 13 and c.y == 15)

type Geometry = interface
    interface Entity
    area() float
    perim() float

type Rect = struct
    width, height float

fn |Rect| area() float
    return .width * .height

fn |Rect| perim() float
    return 2*.width + 2*.height

type Circle = struct
    radius float

fn |Circle| area() float
    return ego::pi * .radius * .radius

fn |Circle| perim() float
    return 2 * ego::pi * .radius

fn measure(g Geometry)
    print "{ego::type_name(g.type)}:\n"
    print "  {g.area()}\n"
    print "  {g.perim()}\n"

fn main()
    const rect = Rect: 3, 4
    const circle = Circle: 5

    const geo = Geometry: Rect: 10,10

    measure(rect);
    measure(circle);
    measure(geo);

type List = struct(T type)
    type This = .type

    data []mut T
    capacity usize

    This()
        return This: .data = _, .capacity = 0
    This(capacity usize)
        return This: .data = &[capacity]T: _, .capacity = capacity
    This(contents []T)
        var buffer = &[contents.len]T: contents
        return This: .data = buffer[:], .capacity = contents.len

    pub fn |This| push(val T)
        if .data.len + 1 > .capacity
            .grow_at_least(1)
        .data = .data[0 .. .data.len + 1]
        .data[-1] = val

    pub fn |This| pop() T
        const back = .data[-1]
        .data = .data[:-1]
        return back

    fn |This| grow_at_least(amt usize)
        var new_buffer = &[.capacity + amt]T: .data, _
        .data = new_buffer[:.capacity]
        .capacity += amt

pub type List = struct
    type T = any

    data []mut T
    buffer []mut T


    init(contents []any)
        .capacity = contents.len
        .data = &[_]mut any: contents
        .T = contents.child_type

    pub fn |List| push(val any)
        if val.type != data.type.child_type
            error "Expected val type `{data.type.child_type}` found `{val.type}`"
        if .data.len + 1 > .capacity
            .grow_capacity(.capacity + 1)
        .data = .data[0:+1]
        .data[-1] = val

var list = List: [_]i32: 1,2,3,4,5,6,7,8

```
