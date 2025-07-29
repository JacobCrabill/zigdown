# Code Blocks and Syntax Highlighting

With the help of TreeSitter, code blocks can be displayed with syntax highlighting!

Use Zigdown to install the TreeSitter parser libraries: `zigdown -p c,cpp,bash,python`

## Examples

```c
#include <stdio.h> /* Comment */
int main() {
  printf("Hello, World!\n");
}
```

```bash
#!/usr/bin/env bash
function say_hello() {
  echo "Hello, ${1}!"
}
```

```python
import os,sys
print("Hello, World!")
```
