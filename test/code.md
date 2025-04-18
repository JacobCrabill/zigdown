# Code Parsing Test

`inline` code

## CPP Code Block

```cpp
#include <stdio.h> /* Comment */
int main() {
    printf("Hello, World!\n");
    const int64_t foo = 1234 + 5678;
    return foo;
}
```

```c++
#include <iostream> // Comment
int main() {
    std::cout << "Hello, World!" << std::endl;
}
```

```c
#include <stdio.h>
int main() {
    printf("Hello, World!\n");
    return 0;
}
```

```zig
const std = @import("std");
pub fn main() !void {
    std.debug.print("Hello, World!\n", .{});
}
```

## JSON `ugh`

```json
{
  "foo": "bar",
  "baz": 2
}
```

## BASH, YAML, None

```bash
echo -e "Hello, World!"
```

```yaml
# TODO: I need to fork the current tree-sitter-yaml Github repo to make it work
root:
  foo: "bar"
  baz: hello
  bash: |
    echo -e Hello, World!
```

```make
# Default target
all: foo bar baz

clean:
    rm foo bar baz
```

```cmake
cmake_minimum_required(VERSION 3.20 FATAL_ERROR)
set(FOO "${BAR}" CACHE "Description" FORCE)
option(DO_STUFF "Do some stuff" ON)
```

```
code with no language set
```
