## Code Parsing Test

`inline` code

# CPP Code Block

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

## JSON `ugh`

```json
{
  "foo": "bar",
  "baz": 2
}
```

```bash
echo -e "Hello, World!"
```

```yaml
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

```
code with no language set
```
