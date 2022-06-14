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
- [numeric literals](#numericliterals)
- [string literals](#stringliterals)
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

Variables are declare with the `var` keyword. The type of a variable will be constrained to the type it was
initialized with. Optionally you can specify a type annotation after the variable name.

```go
var hello = "world" // `hello` is constrained to `string`
var hello2 any = "Earth" // `hello2` is unconstrained
var twice int = true // ERR expected `int`, found `bool`

// unconstrained variables can be reassigned to any type
hello2 = 32
hello2 = false
hello2 = 3.1415926
```

You can asign to muliple variables at once

```go
var x,y,z = 1,2,3

// a,b, and c are all int's initialized to 0
// if a variable declaration statement has exactly one initializer
// it will be used to initialze all variable being declared
var a,b,c = 0
var a int, b bool = false // ERR cannot initialize int with bool

// type annotations can apply to multiple variabe names
var d,e int, name string = 4,8,"Patrick"

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

Constants can be declared with the `const` keyword. Constants are always statically typed and cannot
be re-asigned.

```go
const pi = 3.14159265358927 // type is infered as float
const e any = 2.71828 // ERR constants must have concrete type

pi = 7 // ERR cannot asign to constant `pi`
```

<a name="references"></a>

## references

> TODO

<a name="optionals"></a>

## optionals

> TODO

<a name="numericliterals"></a>

## numeric literals

> TODO

```rust
10
10.11
0b00
0x00
0o00
100'000
```

<a name="stringliterals"></a>

## string literals

> TODO

utf8

```go
var s = "hello string"
```

<a name="arrays"></a>

## arrays

> TODO

```go
var a = [1,2,3,4,5,6]
```

<a name="lists"></a>

## lists

> TODO

```go
var l = list(int): 1,2,3,4,5
l.append(77)
for i,v in l : l[i] = v * 2
var back = l.pop()
assert back == 154
```

<a name="maps"></a>

## maps

> TODO

```go
var m = map(string,any)
    "name" =  "Mayday Monday"
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
if true
    print "statements in a block are indented"
        print ":(" // ERR unexpected indent

if true : print "colons start a single-line block that end at the next newline"

block // anonymous blocks
    var a = 12
    print "a = {a}"
print "a = {a}" // ERR variable `a` is out of scope
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
var i = get_value()

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
var array = [1,2,3,4,5]
for i in array
    print "iteration {i}"
```

<a name="controlflow_func"></a>

### func

> TODO

```go
func name(param param_type) return_type
    return value
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
type month = 1..12 int
type uint = 0..limits.max(int)
type ufloat = 0.0..float.inf

type digit = '0'..'9'
type lower = 'a'..'z'
type upper = 'A'..'Z'
type alpha = lower | upper
type alphanumeric = alpha | digit
```

All these concepts can be mixed in a single type

```go
type alphanumeric = '0'..'9' | 'a'..'z' | 'A'..'Z'
type better_int = int | "NaN" | "INF" | "-INF"
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

Struct values can be created with a struct initializer. Specify the name of the struct, then a block of field initilizers

```go
// all fields must be initialized
// fields with defualt initializers can be omitted
var p = person
    .name = "Patrick"
    .age = 24
    .height = 173

// named designations are optional
// initializers are assigned to fields in order of declaration
var p = person
    "patrick"
    24
    173

// use commas to declare initializers on the same line
var p = person
    "patrick", 24, 173

// use single line block
var p = person: "patrick", 24, 173
```

Standard member access syntax

```go
print "{p.name}" // Patrick
p.name = "Horatio Slim"
print "{p.name}" // Horatio Slim
```

Structs can be destructured into tuples,
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
type serial = interface
    method serialize() string
    method& deserialize(string) &this
    func deserialize(string) this

    // maybe C++20 style requires expressions?
    // requires(t this) : t == t.deserialize(t.serialize())

method file::write_value(value serial)
    .write_string(value.serialize())
```

To have a type support an interface simply implement the necessary [methods](#methods).
If you want to ensure a particular interface is implemented on a given type you can use the `is` operator.

```go
method person::serialize() string
    return fmt "person: .name='{.name}', .age={.age}, .height={.height}, .alive={.alive};"

method& person::deserialize(str string) &person
    this = scan str "person: .name='{:s}', .age={:d}, .height={:d}, .alive={:b};"
    return this

func person::deserialize(str string) person
    var new_person = person: "",0,0
    return new_person.deserialize(str)

assert(person is serial)
```

<a name="usertypes_enum"></a>

### enumeration

> TODO

An enumeration is an enumeration. enumeration.

```go
type direction = enum
    north, south
    east, west

var dir = direction.north
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

Methods are functions that can be called on a value with a period. A method declaration must
be namespaced to the type it's called on. A reference to the
value the method is being called on can be obtained with the `this` keyword. If the value
is of struct type, member access can can have the `this` keyword omited. `this.age == .age`

```go
method person::output()
    if .alive
        print "person: {.name}, {.age} years, {.height}cm"
    else
        print "RIP {.name}"

p.output() // person: Wanda, 500 years, 35cm
(person: "Bob",0,0,false).output() // RIP Bob

// 'this' reference is immutable by defualt
method person::happy_birthday()
    .age += 1 // ERR connot assign to member of immutable reference `this`

// use an ampersand for mutable this
method& person::happy_birthday()
    .age += 1 // OK `this` is mutable

method int::squared() int
    return this * this

const sqr = 5.squared() // 25
```
